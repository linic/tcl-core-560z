// SPDX-License-Identifier: GPL-2.0-only
/*
 *  ALSA driver for the Cirrus Logic CS4237B on boards that do not
 *  expose the CSC0010 "Control" PnP logical device.
 *
 *  Derived from sound/isa/cs423x/cs4236_lib.c (Linux 6.18.8) by
 *  Jaroslav Kysela <perex@perex.cz>. All accesses through the C0..C8
 *  control-port window have been removed: this module talks to the
 *  chip only via the WSS-side direct registers (snd_wss_in/_out) and
 *  the WSS-side indirect "extended" registers (snd_cs4236_ext_in/_out).
 *
 *  Consequences of dropping the control port:
 *    - no S/PDIF (IEC958) controls;
 *    - no hardware 3D effect controls;
 *    - no IEC958 enable switch (which toggles C4 bits);
 *    - no save/restore of cimage[] across suspend/resume;
 *    - no chip-init writes to C0..C8.
 *  Everything that lives behind the WSS port is preserved.
 */

#include <linux/io.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/time.h>
#include <linux/wait.h>
#include <sound/core.h>
#include <sound/wss.h>
#include <sound/asoundef.h>
#include <sound/initval.h>
#include <sound/tlv.h>

#include "cs4237b.h"

/*
 *  Default values for the WSS-side extended ("eimage") registers.
 *  Identical layout to snd_cs4236_ext_map[] in the stock driver — these
 *  registers live behind the WSS index port, not behind the control
 *  port, so the writes are valid on the 560Z.
 */
static const unsigned char snd_cs4237b_ext_map[18] = {
	/* CS4236_LEFT_LINE */		0xff,
	/* CS4236_RIGHT_LINE */		0xff,
	/* CS4236_LEFT_MIC */		0xdf,
	/* CS4236_RIGHT_MIC */		0xdf,
	/* CS4236_LEFT_MIX_CTRL */	0xe0 | 0x18,
	/* CS4236_RIGHT_MIX_CTRL */	0xe0,
	/* CS4236_LEFT_FM */		0xbf,
	/* CS4236_RIGHT_FM */		0xbf,
	/* CS4236_LEFT_DSP */		0xbf,
	/* CS4236_RIGHT_DSP */		0xbf,
	/* CS4236_RIGHT_LOOPBACK */	0xbf,
	/* CS4236_DAC_MUTE */		0xe0,
	/* CS4236_ADC_RATE */		0x01,	/* 48kHz */
	/* CS4236_DAC_RATE */		0x01,	/* 48kHz */
	/* CS4236_LEFT_MASTER */	0xbf,
	/* CS4236_RIGHT_MASTER */	0xbf,
	/* CS4236_LEFT_WAVE */		0xbf,
	/* CS4236_RIGHT_WAVE */		0xbf
};

/*
 *  PCM
 */

#define CLOCKS 8

static const struct snd_ratnum cs4237b_clocks[CLOCKS] = {
	{ .num = 16934400, .den_min = 353, .den_max = 353, .den_step = 1 },
	{ .num = 16934400, .den_min = 529, .den_max = 529, .den_step = 1 },
	{ .num = 16934400, .den_min = 617, .den_max = 617, .den_step = 1 },
	{ .num = 16934400, .den_min = 1058, .den_max = 1058, .den_step = 1 },
	{ .num = 16934400, .den_min = 1764, .den_max = 1764, .den_step = 1 },
	{ .num = 16934400, .den_min = 2117, .den_max = 2117, .den_step = 1 },
	{ .num = 16934400, .den_min = 2558, .den_max = 2558, .den_step = 1 },
	{ .num = 16934400/16, .den_min = 21, .den_max = 192, .den_step = 1 }
};

static const struct snd_pcm_hw_constraint_ratnums cs4237b_hw_constraints_clocks = {
	.nrats = CLOCKS,
	.rats = cs4237b_clocks,
};

static int snd_cs4237b_xrate(struct snd_pcm_runtime *runtime)
{
	return snd_pcm_hw_constraint_ratnums(runtime, 0, SNDRV_PCM_HW_PARAM_RATE,
					     &cs4237b_hw_constraints_clocks);
}

static unsigned char cs4237b_divisor_to_rate_register(unsigned int divisor)
{
	switch (divisor) {
	case 353:	return 1;
	case 529:	return 2;
	case 617:	return 3;
	case 1058:	return 4;
	case 1764:	return 5;
	case 2117:	return 6;
	case 2558:	return 7;
	default:
		if (divisor < 21 || divisor > 192) {
			snd_BUG();
			return 192;
		}
		return divisor;
	}
}

static void snd_cs4237b_playback_format(struct snd_wss *chip,
					struct snd_pcm_hw_params *params,
					unsigned char pdfr)
{
	unsigned char rate = cs4237b_divisor_to_rate_register(params->rate_den);

	guard(spinlock_irqsave)(&chip->reg_lock);
	/* set fast playback format change and clean playback FIFO */
	snd_wss_out(chip, CS4231_ALT_FEATURE_1,
		    chip->image[CS4231_ALT_FEATURE_1] | 0x10);
	snd_wss_out(chip, CS4231_PLAYBK_FORMAT, pdfr & 0xf0);
	snd_wss_out(chip, CS4231_ALT_FEATURE_1,
		    chip->image[CS4231_ALT_FEATURE_1] & ~0x10);
	snd_cs4236_ext_out(chip, CS4236_DAC_RATE, rate);
}

static void snd_cs4237b_capture_format(struct snd_wss *chip,
				       struct snd_pcm_hw_params *params,
				       unsigned char cdfr)
{
	unsigned char rate = cs4237b_divisor_to_rate_register(params->rate_den);

	guard(spinlock_irqsave)(&chip->reg_lock);
	/* set fast capture format change and clean capture FIFO */
	snd_wss_out(chip, CS4231_ALT_FEATURE_1,
		    chip->image[CS4231_ALT_FEATURE_1] | 0x20);
	snd_wss_out(chip, CS4231_REC_FORMAT, cdfr & 0xf0);
	snd_wss_out(chip, CS4231_ALT_FEATURE_1,
		    chip->image[CS4231_ALT_FEATURE_1] & ~0x20);
	snd_cs4236_ext_out(chip, CS4236_ADC_RATE, rate);
}

#ifdef CONFIG_PM

/*
 *  Suspend/resume save and restore only the WSS-side state:
 *    - image[]  : the 32 direct WSS index registers;
 *    - eimage[] : the 18 WSS-side extended registers (CS4236_I23VAL).
 *  cimage[] is the software shadow of the C0..C8 control-port window;
 *  on the 560Z that window is not mapped, so we never touch it.
 */
static void snd_cs4237b_suspend(struct snd_wss *chip)
{
	int reg;

	guard(spinlock_irqsave)(&chip->reg_lock);
	for (reg = 0; reg < 32; reg++)
		chip->image[reg] = snd_wss_in(chip, reg);
	for (reg = 0; reg < 18; reg++)
		chip->eimage[reg] = snd_cs4236_ext_in(chip, CS4236_I23VAL(reg));
}

static void snd_cs4237b_resume(struct snd_wss *chip)
{
	int reg;

	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		for (reg = 0; reg < 32; reg++) {
			switch (reg) {
			case CS4236_EXT_REG:
			case CS4231_VERSION:
				break;
			default:
				snd_wss_out(chip, reg, chip->image[reg]);
				break;
			}
		}
		for (reg = 0; reg < 18; reg++)
			snd_cs4236_ext_out(chip, CS4236_I23VAL(reg),
					   chip->eimage[reg]);
	}
	snd_wss_mce_down(chip);
}

#endif /* CONFIG_PM */

/*
 *  Bring up a CS4237B that has only the WSS PnP logical device wired.
 *  Equivalent to snd_cs4236_create() in the stock driver, with the
 *  control-port code path stripped out:
 *    - calls snd_wss_create() with cport = -1, which the library
 *      already supports (it skips devm_request_region for the cport);
 *    - skips the C1-vs-WSS-extended version cross-check (the C1 read
 *      would land on an unmapped I/O range);
 *    - skips the writes that initialise C0..C8 to known values, for
 *      the same reason;
 *    - validates that the WSS-extended CS4236_VERSION register reports
 *      a CS4237B (chip id 0x08), and refuses to bind otherwise.
 */
int snd_cs4237b_create(struct snd_card *card,
		       unsigned long port,
		       int irq, int dma1, int dma2,
		       struct snd_wss **rchip)
{
	struct snd_wss *chip;
	unsigned char ver;
	unsigned int reg;
	int err;

	*rchip = NULL;

	err = snd_wss_create(card, port, -1, irq, dma1, dma2,
			     WSS_HW_DETECT3, 0, &chip);
	if (err < 0)
		return err;

	if ((chip->hardware & WSS_HW_CS4236B_MASK) == 0) {
		dev_err(card->dev,
			"snd-cs4237b: detected hardware 0x%x is not a CS4236B+ chip\n",
			chip->hardware);
		return -ENODEV;
	}

	ver = snd_cs4236_ext_in(chip, CS4236_VERSION);
	dev_info(card->dev,
		 "snd-cs4237b: WSS-side CS4236_VERSION = 0x%02x (chip id 0x%02x, rev 0x%x)\n",
		 ver, ver & 0x1f, (ver >> 5) & 0x7);
	if ((ver & 0x1f) != 0x08) {
		dev_err(card->dev,
			"snd-cs4237b: chip id 0x%02x is not CS4237B (0x08); refusing to bind\n",
			ver & 0x1f);
		return -ENODEV;
	}

	chip->rate_constraint = snd_cs4237b_xrate;
	chip->set_playback_format = snd_cs4237b_playback_format;
	chip->set_capture_format = snd_cs4237b_capture_format;
#ifdef CONFIG_PM
	chip->suspend = snd_cs4237b_suspend;
	chip->resume = snd_cs4237b_resume;
#endif

	/* initialise extended (WSS-side) registers */
	for (reg = 0; reg < ARRAY_SIZE(snd_cs4237b_ext_map); reg++)
		snd_cs4236_ext_out(chip, CS4236_I23VAL(reg),
				   snd_cs4237b_ext_map[reg]);

	/* compatible WSS-side direct registers */
	snd_wss_out(chip, CS4231_LEFT_INPUT, 0x40);
	snd_wss_out(chip, CS4231_RIGHT_INPUT, 0x40);
	snd_wss_out(chip, CS4231_AUX1_LEFT_INPUT, 0xff);
	snd_wss_out(chip, CS4231_AUX1_RIGHT_INPUT, 0xff);
	snd_wss_out(chip, CS4231_AUX2_LEFT_INPUT, 0xdf);
	snd_wss_out(chip, CS4231_AUX2_RIGHT_INPUT, 0xdf);
	snd_wss_out(chip, CS4231_RIGHT_LINE_IN, 0xff);
	snd_wss_out(chip, CS4231_LEFT_LINE_IN, 0xff);
	snd_wss_out(chip, CS4231_RIGHT_LINE_IN, 0xff);

	*rchip = chip;
	return 0;
}
EXPORT_SYMBOL(snd_cs4237b_create);

int snd_cs4237b_pcm(struct snd_wss *chip, int device)
{
	int err;

	err = snd_wss_pcm(chip, device);
	if (err < 0)
		return err;
	chip->pcm->info_flags &= ~SNDRV_PCM_INFO_JOINT_DUPLEX;
	return 0;
}
EXPORT_SYMBOL(snd_cs4237b_pcm);

/*
 *  MIXER
 *
 *  Only WSS-side controls are registered. Controls that the stock
 *  driver gates behind the control port (IEC958 enable, IEC958
 *  channel-status bytes, 3D effects) are intentionally omitted.
 */

#define CS4237B_SINGLE(xname, xindex, reg, shift, mask, invert) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .info = snd_cs4237b_info_single, \
  .get = snd_cs4237b_get_single, .put = snd_cs4237b_put_single, \
  .private_value = reg | (shift << 8) | (mask << 16) | (invert << 24) }

#define CS4237B_SINGLE_TLV(xname, xindex, reg, shift, mask, invert, xtlv) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .access = SNDRV_CTL_ELEM_ACCESS_READWRITE | SNDRV_CTL_ELEM_ACCESS_TLV_READ, \
  .info = snd_cs4237b_info_single, \
  .get = snd_cs4237b_get_single, .put = snd_cs4237b_put_single, \
  .private_value = reg | (shift << 8) | (mask << 16) | (invert << 24), \
  .tlv = { .p = (xtlv) } }

static int snd_cs4237b_info_single(struct snd_kcontrol *kcontrol,
				   struct snd_ctl_elem_info *uinfo)
{
	int mask = (kcontrol->private_value >> 16) & 0xff;

	uinfo->type = mask == 1 ? SNDRV_CTL_ELEM_TYPE_BOOLEAN
				: SNDRV_CTL_ELEM_TYPE_INTEGER;
	uinfo->count = 1;
	uinfo->value.integer.min = 0;
	uinfo->value.integer.max = mask;
	return 0;
}

static int snd_cs4237b_get_single(struct snd_kcontrol *kcontrol,
				  struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int reg = kcontrol->private_value & 0xff;
	int shift = (kcontrol->private_value >> 8) & 0xff;
	int mask = (kcontrol->private_value >> 16) & 0xff;
	int invert = (kcontrol->private_value >> 24) & 0xff;

	guard(spinlock_irqsave)(&chip->reg_lock);
	ucontrol->value.integer.value[0] =
		(chip->eimage[CS4236_REG(reg)] >> shift) & mask;
	if (invert)
		ucontrol->value.integer.value[0] =
			mask - ucontrol->value.integer.value[0];
	return 0;
}

static int snd_cs4237b_put_single(struct snd_kcontrol *kcontrol,
				  struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int reg = kcontrol->private_value & 0xff;
	int shift = (kcontrol->private_value >> 8) & 0xff;
	int mask = (kcontrol->private_value >> 16) & 0xff;
	int invert = (kcontrol->private_value >> 24) & 0xff;
	int change;
	unsigned short val;

	val = (ucontrol->value.integer.value[0] & mask);
	if (invert)
		val = mask - val;
	val <<= shift;
	guard(spinlock_irqsave)(&chip->reg_lock);
	val = (chip->eimage[CS4236_REG(reg)] & ~(mask << shift)) | val;
	change = val != chip->eimage[CS4236_REG(reg)];
	snd_cs4236_ext_out(chip, reg, val);
	return change;
}

#define CS4237B_DOUBLE(xname, xindex, left_reg, right_reg, shift_left, shift_right, mask, invert) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .info = snd_cs4237b_info_double, \
  .get = snd_cs4237b_get_double, .put = snd_cs4237b_put_double, \
  .private_value = left_reg | (right_reg << 8) | (shift_left << 16) | \
		   (shift_right << 19) | (mask << 24) | (invert << 22) }

#define CS4237B_DOUBLE_TLV(xname, xindex, left_reg, right_reg, shift_left, \
			   shift_right, mask, invert, xtlv) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .access = SNDRV_CTL_ELEM_ACCESS_READWRITE | SNDRV_CTL_ELEM_ACCESS_TLV_READ, \
  .info = snd_cs4237b_info_double, \
  .get = snd_cs4237b_get_double, .put = snd_cs4237b_put_double, \
  .private_value = left_reg | (right_reg << 8) | (shift_left << 16) | \
		   (shift_right << 19) | (mask << 24) | (invert << 22), \
  .tlv = { .p = (xtlv) } }

static int snd_cs4237b_info_double(struct snd_kcontrol *kcontrol,
				   struct snd_ctl_elem_info *uinfo)
{
	int mask = (kcontrol->private_value >> 24) & 0xff;

	uinfo->type = mask == 1 ? SNDRV_CTL_ELEM_TYPE_BOOLEAN
				: SNDRV_CTL_ELEM_TYPE_INTEGER;
	uinfo->count = 2;
	uinfo->value.integer.min = 0;
	uinfo->value.integer.max = mask;
	return 0;
}

static int snd_cs4237b_get_double(struct snd_kcontrol *kcontrol,
				  struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int left_reg = kcontrol->private_value & 0xff;
	int right_reg = (kcontrol->private_value >> 8) & 0xff;
	int shift_left = (kcontrol->private_value >> 16) & 0x07;
	int shift_right = (kcontrol->private_value >> 19) & 0x07;
	int mask = (kcontrol->private_value >> 24) & 0xff;
	int invert = (kcontrol->private_value >> 22) & 1;

	guard(spinlock_irqsave)(&chip->reg_lock);
	ucontrol->value.integer.value[0] =
		(chip->eimage[CS4236_REG(left_reg)] >> shift_left) & mask;
	ucontrol->value.integer.value[1] =
		(chip->eimage[CS4236_REG(right_reg)] >> shift_right) & mask;
	if (invert) {
		ucontrol->value.integer.value[0] =
			mask - ucontrol->value.integer.value[0];
		ucontrol->value.integer.value[1] =
			mask - ucontrol->value.integer.value[1];
	}
	return 0;
}

static int snd_cs4237b_put_double(struct snd_kcontrol *kcontrol,
				  struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int left_reg = kcontrol->private_value & 0xff;
	int right_reg = (kcontrol->private_value >> 8) & 0xff;
	int shift_left = (kcontrol->private_value >> 16) & 0x07;
	int shift_right = (kcontrol->private_value >> 19) & 0x07;
	int mask = (kcontrol->private_value >> 24) & 0xff;
	int invert = (kcontrol->private_value >> 22) & 1;
	int change;
	unsigned short val1, val2;

	val1 = ucontrol->value.integer.value[0] & mask;
	val2 = ucontrol->value.integer.value[1] & mask;
	if (invert) {
		val1 = mask - val1;
		val2 = mask - val2;
	}
	val1 <<= shift_left;
	val2 <<= shift_right;
	guard(spinlock_irqsave)(&chip->reg_lock);
	if (left_reg != right_reg) {
		val1 = (chip->eimage[CS4236_REG(left_reg)] &
			~(mask << shift_left)) | val1;
		val2 = (chip->eimage[CS4236_REG(right_reg)] &
			~(mask << shift_right)) | val2;
		change = val1 != chip->eimage[CS4236_REG(left_reg)] ||
			 val2 != chip->eimage[CS4236_REG(right_reg)];
		snd_cs4236_ext_out(chip, left_reg, val1);
		snd_cs4236_ext_out(chip, right_reg, val2);
	} else {
		val1 = (chip->eimage[CS4236_REG(left_reg)] &
			~((mask << shift_left) | (mask << shift_right))) |
		       val1 | val2;
		change = val1 != chip->eimage[CS4236_REG(left_reg)];
		snd_cs4236_ext_out(chip, left_reg, val1);
	}
	return change;
}

#define CS4237B_DOUBLE1(xname, xindex, left_reg, right_reg, shift_left, \
			shift_right, mask, invert) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .info = snd_cs4237b_info_double, \
  .get = snd_cs4237b_get_double1, .put = snd_cs4237b_put_double1, \
  .private_value = left_reg | (right_reg << 8) | (shift_left << 16) | \
		   (shift_right << 19) | (mask << 24) | (invert << 22) }

#define CS4237B_DOUBLE1_TLV(xname, xindex, left_reg, right_reg, shift_left, \
			    shift_right, mask, invert, xtlv) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .access = SNDRV_CTL_ELEM_ACCESS_READWRITE | SNDRV_CTL_ELEM_ACCESS_TLV_READ, \
  .info = snd_cs4237b_info_double, \
  .get = snd_cs4237b_get_double1, .put = snd_cs4237b_put_double1, \
  .private_value = left_reg | (right_reg << 8) | (shift_left << 16) | \
		   (shift_right << 19) | (mask << 24) | (invert << 22), \
  .tlv = { .p = (xtlv) } }

static int snd_cs4237b_get_double1(struct snd_kcontrol *kcontrol,
				   struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int left_reg = kcontrol->private_value & 0xff;
	int right_reg = (kcontrol->private_value >> 8) & 0xff;
	int shift_left = (kcontrol->private_value >> 16) & 0x07;
	int shift_right = (kcontrol->private_value >> 19) & 0x07;
	int mask = (kcontrol->private_value >> 24) & 0xff;
	int invert = (kcontrol->private_value >> 22) & 1;

	guard(spinlock_irqsave)(&chip->reg_lock);
	ucontrol->value.integer.value[0] =
		(chip->image[left_reg] >> shift_left) & mask;
	ucontrol->value.integer.value[1] =
		(chip->eimage[CS4236_REG(right_reg)] >> shift_right) & mask;
	if (invert) {
		ucontrol->value.integer.value[0] =
			mask - ucontrol->value.integer.value[0];
		ucontrol->value.integer.value[1] =
			mask - ucontrol->value.integer.value[1];
	}
	return 0;
}

static int snd_cs4237b_put_double1(struct snd_kcontrol *kcontrol,
				   struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int left_reg = kcontrol->private_value & 0xff;
	int right_reg = (kcontrol->private_value >> 8) & 0xff;
	int shift_left = (kcontrol->private_value >> 16) & 0x07;
	int shift_right = (kcontrol->private_value >> 19) & 0x07;
	int mask = (kcontrol->private_value >> 24) & 0xff;
	int invert = (kcontrol->private_value >> 22) & 1;
	int change;
	unsigned short val1, val2;

	val1 = ucontrol->value.integer.value[0] & mask;
	val2 = ucontrol->value.integer.value[1] & mask;
	if (invert) {
		val1 = mask - val1;
		val2 = mask - val2;
	}
	val1 <<= shift_left;
	val2 <<= shift_right;
	guard(spinlock_irqsave)(&chip->reg_lock);
	val1 = (chip->image[left_reg] & ~(mask << shift_left)) | val1;
	val2 = (chip->eimage[CS4236_REG(right_reg)] &
		~(mask << shift_right)) | val2;
	change = val1 != chip->image[left_reg] ||
		 val2 != chip->eimage[CS4236_REG(right_reg)];
	snd_wss_out(chip, left_reg, val1);
	snd_cs4236_ext_out(chip, right_reg, val2);
	return change;
}

#define CS4237B_MASTER_DIGITAL(xname, xindex, xtlv) \
{ .iface = SNDRV_CTL_ELEM_IFACE_MIXER, .name = xname, .index = xindex, \
  .access = SNDRV_CTL_ELEM_ACCESS_READWRITE | SNDRV_CTL_ELEM_ACCESS_TLV_READ, \
  .info = snd_cs4237b_info_double, \
  .get = snd_cs4237b_get_master_digital, \
  .put = snd_cs4237b_put_master_digital, \
  .private_value = 71 << 24, \
  .tlv = { .p = (xtlv) } }

static inline int cs4237b_master_digital_invert_volume(int vol)
{
	return (vol < 64) ? 63 - vol : 64 + (71 - vol);
}

static int snd_cs4237b_get_master_digital(struct snd_kcontrol *kcontrol,
					  struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);

	guard(spinlock_irqsave)(&chip->reg_lock);
	ucontrol->value.integer.value[0] =
		cs4237b_master_digital_invert_volume(
			chip->eimage[CS4236_REG(CS4236_LEFT_MASTER)] & 0x7f);
	ucontrol->value.integer.value[1] =
		cs4237b_master_digital_invert_volume(
			chip->eimage[CS4236_REG(CS4236_RIGHT_MASTER)] & 0x7f);
	return 0;
}

static int snd_cs4237b_put_master_digital(struct snd_kcontrol *kcontrol,
					  struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int change;
	unsigned short val1, val2;

	val1 = cs4237b_master_digital_invert_volume(
		ucontrol->value.integer.value[0] & 0x7f);
	val2 = cs4237b_master_digital_invert_volume(
		ucontrol->value.integer.value[1] & 0x7f);
	guard(spinlock_irqsave)(&chip->reg_lock);
	val1 = (chip->eimage[CS4236_REG(CS4236_LEFT_MASTER)] & ~0x7f) | val1;
	val2 = (chip->eimage[CS4236_REG(CS4236_RIGHT_MASTER)] & ~0x7f) | val2;
	change = val1 != chip->eimage[CS4236_REG(CS4236_LEFT_MASTER)] ||
		 val2 != chip->eimage[CS4236_REG(CS4236_RIGHT_MASTER)];
	snd_cs4236_ext_out(chip, CS4236_LEFT_MASTER, val1);
	snd_cs4236_ext_out(chip, CS4236_RIGHT_MASTER, val2);
	return change;
}

static const DECLARE_TLV_DB_SCALE(db_scale_7bit, -9450, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_6bit, -9450, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_6bit_12db_max, -8250, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_5bit_12db_max, -3450, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_5bit_22db_max, -2400, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_4bit, -4500, 300, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_2bit, -1800, 600, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_rec_gain, 0, 150, 0);

static const struct snd_kcontrol_new snd_cs4237b_controls[] = {

CS4237B_DOUBLE("Master Digital Playback Switch", 0,
		CS4236_LEFT_MASTER, CS4236_RIGHT_MASTER, 7, 7, 1, 1),
CS4237B_DOUBLE("Master Digital Capture Switch", 0,
		CS4236_DAC_MUTE, CS4236_DAC_MUTE, 7, 6, 1, 1),
CS4237B_MASTER_DIGITAL("Master Digital Volume", 0, db_scale_7bit),

CS4237B_DOUBLE_TLV("Capture Boost Volume", 0,
		   CS4236_LEFT_MIX_CTRL, CS4236_RIGHT_MIX_CTRL, 5, 5, 3, 1,
		   db_scale_2bit),

WSS_DOUBLE("PCM Playback Switch", 0,
		CS4231_LEFT_OUTPUT, CS4231_RIGHT_OUTPUT, 7, 7, 1, 1),
WSS_DOUBLE_TLV("PCM Playback Volume", 0,
		CS4231_LEFT_OUTPUT, CS4231_RIGHT_OUTPUT, 0, 0, 63, 1,
		db_scale_6bit),

CS4237B_DOUBLE("DSP Playback Switch", 0,
		CS4236_LEFT_DSP, CS4236_RIGHT_DSP, 7, 7, 1, 1),
CS4237B_DOUBLE_TLV("DSP Playback Volume", 0,
		   CS4236_LEFT_DSP, CS4236_RIGHT_DSP, 0, 0, 63, 1,
		   db_scale_6bit),

CS4237B_DOUBLE("FM Playback Switch", 0,
		CS4236_LEFT_FM, CS4236_RIGHT_FM, 7, 7, 1, 1),
CS4237B_DOUBLE_TLV("FM Playback Volume", 0,
		   CS4236_LEFT_FM, CS4236_RIGHT_FM, 0, 0, 63, 1,
		   db_scale_6bit),

CS4237B_DOUBLE("Wavetable Playback Switch", 0,
		CS4236_LEFT_WAVE, CS4236_RIGHT_WAVE, 7, 7, 1, 1),
CS4237B_DOUBLE_TLV("Wavetable Playback Volume", 0,
		   CS4236_LEFT_WAVE, CS4236_RIGHT_WAVE, 0, 0, 63, 1,
		   db_scale_6bit_12db_max),

WSS_DOUBLE("Synth Playback Switch", 0,
		CS4231_LEFT_LINE_IN, CS4231_RIGHT_LINE_IN, 7, 7, 1, 1),
WSS_DOUBLE_TLV("Synth Volume", 0,
		CS4231_LEFT_LINE_IN, CS4231_RIGHT_LINE_IN, 0, 0, 31, 1,
		db_scale_5bit_12db_max),
WSS_DOUBLE("Synth Capture Switch", 0,
		CS4231_LEFT_LINE_IN, CS4231_RIGHT_LINE_IN, 6, 6, 1, 1),
WSS_DOUBLE("Synth Capture Bypass", 0,
		CS4231_LEFT_LINE_IN, CS4231_RIGHT_LINE_IN, 5, 5, 1, 1),

CS4237B_DOUBLE("Mic Playback Switch", 0,
		CS4236_LEFT_MIC, CS4236_RIGHT_MIC, 6, 6, 1, 1),
CS4237B_DOUBLE("Mic Capture Switch", 0,
		CS4236_LEFT_MIC, CS4236_RIGHT_MIC, 7, 7, 1, 1),
CS4237B_DOUBLE_TLV("Mic Volume", 0, CS4236_LEFT_MIC, CS4236_RIGHT_MIC,
		   0, 0, 31, 1, db_scale_5bit_22db_max),
CS4237B_DOUBLE("Mic Playback Boost (+20dB)", 0,
		CS4236_LEFT_MIC, CS4236_RIGHT_MIC, 5, 5, 1, 0),

WSS_DOUBLE("Line Playback Switch", 0,
		CS4231_AUX1_LEFT_INPUT, CS4231_AUX1_RIGHT_INPUT, 7, 7, 1, 1),
WSS_DOUBLE_TLV("Line Volume", 0,
		CS4231_AUX1_LEFT_INPUT, CS4231_AUX1_RIGHT_INPUT, 0, 0, 31, 1,
		db_scale_5bit_12db_max),
WSS_DOUBLE("Line Capture Switch", 0,
		CS4231_AUX1_LEFT_INPUT, CS4231_AUX1_RIGHT_INPUT, 6, 6, 1, 1),
WSS_DOUBLE("Line Capture Bypass", 0,
		CS4231_AUX1_LEFT_INPUT, CS4231_AUX1_RIGHT_INPUT, 5, 5, 1, 1),

WSS_DOUBLE("CD Playback Switch", 0,
		CS4231_AUX2_LEFT_INPUT, CS4231_AUX2_RIGHT_INPUT, 7, 7, 1, 1),
WSS_DOUBLE_TLV("CD Volume", 0,
		CS4231_AUX2_LEFT_INPUT, CS4231_AUX2_RIGHT_INPUT, 0, 0, 31, 1,
		db_scale_5bit_12db_max),
WSS_DOUBLE("CD Capture Switch", 0,
		CS4231_AUX2_LEFT_INPUT, CS4231_AUX2_RIGHT_INPUT, 6, 6, 1, 1),

CS4237B_DOUBLE1("Mono Output Playback Switch", 0,
		CS4231_MONO_CTRL, CS4236_RIGHT_MIX_CTRL, 6, 7, 1, 1),
CS4237B_DOUBLE1("Beep Playback Switch", 0,
		CS4231_MONO_CTRL, CS4236_LEFT_MIX_CTRL, 7, 7, 1, 1),
WSS_SINGLE_TLV("Beep Playback Volume", 0, CS4231_MONO_CTRL, 0, 15, 1,
		db_scale_4bit),
WSS_SINGLE("Beep Bypass Playback Switch", 0, CS4231_MONO_CTRL, 5, 1, 0),

WSS_DOUBLE_TLV("Capture Volume", 0, CS4231_LEFT_INPUT, CS4231_RIGHT_INPUT,
		0, 0, 15, 0, db_scale_rec_gain),
WSS_DOUBLE("Analog Loopback Capture Switch", 0,
		CS4231_LEFT_INPUT, CS4231_RIGHT_INPUT, 7, 7, 1, 0),

WSS_SINGLE("Loopback Digital Playback Switch", 0, CS4231_LOOPBACK, 0, 1, 0),
CS4237B_DOUBLE1_TLV("Loopback Digital Playback Volume", 0,
		    CS4231_LOOPBACK, CS4236_RIGHT_LOOPBACK, 2, 0, 63, 1,
		    db_scale_6bit),
};

int snd_cs4237b_mixer(struct snd_wss *chip)
{
	struct snd_card *card;
	unsigned int idx;
	int err;

	if (snd_BUG_ON(!chip || !chip->card))
		return -EINVAL;
	card = chip->card;
	strscpy(card->mixername, snd_wss_chip_id(chip));

	for (idx = 0; idx < ARRAY_SIZE(snd_cs4237b_controls); idx++) {
		err = snd_ctl_add(card,
				  snd_ctl_new1(&snd_cs4237b_controls[idx],
					       chip));
		if (err < 0)
			return err;
	}
	return 0;
}
EXPORT_SYMBOL(snd_cs4237b_mixer);
