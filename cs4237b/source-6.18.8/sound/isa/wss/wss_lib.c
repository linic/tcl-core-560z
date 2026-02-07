// SPDX-License-Identifier: GPL-2.0-or-later
/*
 *  Copyright (c) by Jaroslav Kysela <perex@perex.cz>
 *
 *  Edited by linic@hotmail.ca.
 *  Routines for control of CS4237B for the ThinkPad 560Z
 *
 *  Note:
 *  - Removed control port since my 560z doesn't expose the control device.
 *  - Removed many hardware checks since my 560z is successfully detected as a WSS_HW_CS4237B.
 *  - After the module has loaded, run "sudo alsactl init CS4237B" and then "alsamixer" to up the volumes.
 *    "sudo alsactl store CS4237B" can be used to save the alsa settings including the volumes.
 *    After a reboot, "sudo alsactl init CS4237B" and "sudo alsactl restore CS4237B" are needed for
 *    sound to be audible.
 *
 */

#include <linux/delay.h>
#include <linux/pm.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/slab.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/io.h>
#include <sound/core.h>
#include <sound/wss.h>
#include <sound/pcm_params.h>
#include <sound/tlv.h>

#include <asm/dma.h>
#include <asm/irq.h>

MODULE_AUTHOR("Jaroslav Kysela <perex@perex.cz>");
MODULE_DESCRIPTION("Routines for control of CS4231(A)/CS4232/InterWave & compatible chips");
MODULE_LICENSE("GPL");

/*
 *  Some variables
 */

static const unsigned char freq_bits[14] = {
	/* 5510 */	0x00 | CS4231_XTAL2,
	/* 6620 */	0x0E | CS4231_XTAL2,
	/* 8000 */	0x00 | CS4231_XTAL1,
	/* 9600 */	0x0E | CS4231_XTAL1,
	/* 11025 */	0x02 | CS4231_XTAL2,
	/* 16000 */	0x02 | CS4231_XTAL1,
	/* 18900 */	0x04 | CS4231_XTAL2,
	/* 22050 */	0x06 | CS4231_XTAL2,
	/* 27042 */	0x04 | CS4231_XTAL1,
	/* 32000 */	0x06 | CS4231_XTAL1,
	/* 33075 */	0x0C | CS4231_XTAL2,
	/* 37800 */	0x08 | CS4231_XTAL2,
	/* 44100 */	0x0A | CS4231_XTAL2,
	/* 48000 */	0x0C | CS4231_XTAL1
};

static const unsigned int rates[14] = {
	5510, 6620, 8000, 9600, 11025, 16000, 18900, 22050,
	27042, 32000, 33075, 37800, 44100, 48000
};

static const struct snd_pcm_hw_constraint_list hw_constraints_rates = {
	.count = ARRAY_SIZE(rates),
	.list = rates,
	.mask = 0,
};

static int snd_wss_xrate(struct snd_pcm_runtime *runtime)
{
	return snd_pcm_hw_constraint_list(runtime, 0, SNDRV_PCM_HW_PARAM_RATE,
					  &hw_constraints_rates);
}

static const unsigned char snd_wss_original_image[32] =
{
	0x00,			/* 00/00 - lic */
	0x00,			/* 01/01 - ric */
	0x9f,			/* 02/02 - la1ic */
	0x9f,			/* 03/03 - ra1ic */
	0x9f,			/* 04/04 - la2ic */
	0x9f,			/* 05/05 - ra2ic */
	0xbf,			/* 06/06 - loc */
	0xbf,			/* 07/07 - roc */
	0x20,			/* 08/08 - pdfr */
	CS4231_AUTOCALIB,	/* 09/09 - ic */
	0x00,			/* 0a/10 - pc */
	0x00,			/* 0b/11 - ti */
	CS4231_MODE2,		/* 0c/12 - mi */
	0xfc,			/* 0d/13 - lbc */
	0x00,			/* 0e/14 - pbru */
	0x00,			/* 0f/15 - pbrl */
	0x80,			/* 10/16 - afei */
	0x01,			/* 11/17 - afeii */
	0x9f,			/* 12/18 - llic */
	0x9f,			/* 13/19 - rlic */
	0x00,			/* 14/20 - tlb */
	0x00,			/* 15/21 - thb */
	0x00,			/* 16/22 - la3mic/reserved */
	0x00,			/* 17/23 - ra3mic/reserved */
	0x00,			/* 18/24 - afs */
	0x00,			/* 19/25 - lamoc/version */
	0xcf,			/* 1a/26 - mioc */
	0x00,			/* 1b/27 - ramoc/reserved */
	0x20,			/* 1c/28 - cdfr */
	0x00,			/* 1d/29 - res4 */
	0x00,			/* 1e/30 - cbru */
	0x00,			/* 1f/31 - cbrl */
};

static const unsigned char snd_opti93x_original_image[32] =
{
	0x00,		/* 00/00 - l_mixout_outctrl */
	0x00,		/* 01/01 - r_mixout_outctrl */
	0x88,		/* 02/02 - l_cd_inctrl */
	0x88,		/* 03/03 - r_cd_inctrl */
	0x88,		/* 04/04 - l_a1/fm_inctrl */
	0x88,		/* 05/05 - r_a1/fm_inctrl */
	0x80,		/* 06/06 - l_dac_inctrl */
	0x80,		/* 07/07 - r_dac_inctrl */
	0x00,		/* 08/08 - ply_dataform_reg */
	0x00,		/* 09/09 - if_conf */
	0x00,		/* 0a/10 - pin_ctrl */
	0x00,		/* 0b/11 - err_init_reg */
	0x0a,		/* 0c/12 - id_reg */
	0x00,		/* 0d/13 - reserved */
	0x00,		/* 0e/14 - ply_upcount_reg */
	0x00,		/* 0f/15 - ply_lowcount_reg */
	0x88,		/* 10/16 - reserved/l_a1_inctrl */
	0x88,		/* 11/17 - reserved/r_a1_inctrl */
	0x88,		/* 12/18 - l_line_inctrl */
	0x88,		/* 13/19 - r_line_inctrl */
	0x88,		/* 14/20 - l_mic_inctrl */
	0x88,		/* 15/21 - r_mic_inctrl */
	0x80,		/* 16/22 - l_out_outctrl */
	0x80,		/* 17/23 - r_out_outctrl */
	0x00,		/* 18/24 - reserved */
	0x00,		/* 19/25 - reserved */
	0x00,		/* 1a/26 - reserved */
	0x00,		/* 1b/27 - reserved */
	0x00,		/* 1c/28 - cap_dataform_reg */
	0x00,		/* 1d/29 - reserved */
	0x00,		/* 1e/30 - cap_upcount_reg */
	0x00		/* 1f/31 - cap_lowcount_reg */
};

/*
 *  Basic I/O functions
 */

static inline void wss_outb(struct snd_wss *chip, u8 offset, u8 val)
{
	outb(val, chip->port + offset);
}

static inline u8 wss_inb(struct snd_wss *chip, u8 offset)
{
	return inb(chip->port + offset);
}

/* Wait for the INIT bit to be 0. */
static void snd_wss_wait_delay(struct snd_wss *chip, unsigned char delay_microseconds)
{
	unsigned char i0, timeout;
	bool is_init_set;

	i0 = wss_inb(chip, CS4231P(REGSEL));
	is_init_set = i0 & CS4231_INIT;
	for (timeout = 250; timeout > 0 && is_init_set; timeout--) {
		udelay(delay_microseconds);
		i0 = wss_inb(chip, CS4231P(REGSEL));
		is_init_set = i0 & CS4231_INIT;
	}
	if (is_init_set) {
		dev_err(chip->card->dev, "snd_wss_wait - INIT is still 1. I0=0x%x\n", i0);
	}
}

static void snd_wss_wait(struct snd_wss *chip)
{
	/* This loop timeouts roughly 0.025 second. */
	snd_wss_wait_delay(chip, 100);
}

/* Functionally similar to snd_wss_out, but the waiting time between each INIT check
 * is 10 microseconds instead of 100 microseconds. I'm not sure why, but since it works
 * I stopped investigating. */
static void snd_wss_dout(struct snd_wss *chip, unsigned char reg,
			 unsigned char value)
{
	/* This loop timeouts roughly after 0.0025 second. */
	snd_wss_wait_delay(chip, 10);
	wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | reg);
	wss_outb(chip, CS4231P(REG), value);
	mb();
}

/* Select an index register and write a new value to it. */
void snd_wss_out(struct snd_wss *chip, unsigned char index_register_address, unsigned char index_register_new_value)
{
	snd_wss_wait(chip);
	/* CS4231P(REGSEL) is 0 which is R0, the Index Address Register.
	 * This writes the value of reg on it keeping the last known value of mce_bit.
	 * This is only useful to change IA0 to IA4 and change the values on the Index Data Register. */
	wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | index_register_address);
	/* CS4231P(REG) is 1 which is R1, the Index Data Register.
	 * During initialization and software power down
	 * of the WSS Codec, this register can NOT be
	 * written and is always read 10000000 (80h) */
	wss_outb(chip, CS4231P(REG), index_register_new_value);
	/* Save the latest written state in chip->image. */
	chip->image[index_register_address] = index_register_new_value;
	/* mb() prevents loads and stores being reordered across this point */
	mb();
}
EXPORT_SYMBOL(snd_wss_out);

/* Read value from an index register "reg" and return it. */
unsigned char snd_wss_in(struct snd_wss *chip, unsigned char reg)
{
	unsigned char index_register_value;
	snd_wss_wait(chip);
	wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | reg);
	mb();
	return wss_inb(chip, CS4231P(REG));
}

/* Make this function available to other drivers. */
EXPORT_SYMBOL(snd_wss_in);

/* Write a value on an extended register. */
void snd_cs4236_ext_out(struct snd_wss *chip,
		unsigned char extended_register_address,
		unsigned char new_value)
{
	/* 0x17 selects I23
	 * Extended Register Access (I23)
	 * D7  D6  D5  D4  D3   D2  D1  D0
	 * XA3 XA2 XA1 XA0 XRAE XA4 res ACF
	 * Table 16. WSS Extended Register Control
	 * +--------+---------------------------------------+
	 * | Index  | Register Name                         |
	 * +--------+---------------------------------------+
	 * | X0     | Left LINE Alternate Volume            |
	 * | X1     | Right LINE Alternate Volume           |
	 * | X2     | Left MIC Volume                       |
	 * | X3     | Right MIC Volume                      |
	 * | X4     | Synthesis and Input Mixer Control     |
	 * | X5     | Right Input Mixer Control             |
	 * | X6     | Left FM Synthesis Volume              |
	 * | X7     | Right FM Synthesis Volume             |
	 * | X8     | Left DSP Serial Port Volume           |
	 * | X9     | Right DSP Serial Port Volume          |
	 * | X10    | Right Loopback Monitor Volume         |
	 * | X11    | DAC Mute and IFSE Enable              |
	 * | X12    | Independent ADC Sample Freq.          |
	 * | X13    | Independent DAC Sample Freq.          |
	 * | X14    | Left Master Digital Audio Volume      |
	 * | X15    | Right Master Digital Audio Volume     |
	 * | X16    | Left Wavetable Serial Port Volume     |
	 * | X17    | Right Wavetable Serial Port Volume    |
	 * | X18-X24| Reserved                              |
	 * | X25    | Chip Version and ID                   |
	 * +--------+---------------------------------------+ 
	 * CS4231 Control Register Bit Descriptions
	 * +----------+---------------------------------------------+
	 * | Bit Name | Description                                 |
	 * +----------+---------------------------------------------+
	 * | ACF      | ADPCM Capture Freeze. When set,             |
	 * |          | the capture ADPCM accumulator               |
	 * |          | and step size are frozen. This bit          |
	 * |          | must be set to zero for adaptation to       |
	 * |          | continue. This bit is used when             |
	 * |          | pausing a ADPCM capture stream.             |
	 * +----------+---------------------------------------------+
	 * | res      | Reserved. Must write 0. Could read          |
	 * |          | as 0 or 1.                                  |
	 * +----------+---------------------------------------------+
	 * | XA4      | Extended Register Address bit 4.            |
	 * |          | Along with XA3-XA0, enables ac-             |
	 * |          | cess to extended registers X16,             |
	 * |          | X17, and X25. MODE 3 only.                  |
	 * +----------+---------------------------------------------+
	 * | XRAE     | Extended Register Access Enable.            |
	 * |          | Setting this bit converts this register     |
	 * |          | from the extended address register          |
	 * |          | to the extended data register. To con-      |
	 * |          | vert back to an address register, R0        |
	 * |          | must be written. MODE 3 only.               |
	 * +----------+---------------------------------------------+
	 * | XA3-XA0  | Extended Register Address. Along            |
	 * |          | with XA4, sets the register number          |
	 * |          | (X0-X17+X25) accessed when                  |
	 * |          | XRAE is set. MODE 3 only. See the           |
	 * |          | WSS Extended Register section for           |
	 * |          | more details.                               |
	 * +----------+---------------------------------------------+
	 * I23 acts
	 * as both the extended address and extended data
	 * register. These extended registers are only avail-
	 * able when in MODE 3.
	 * Accessing the X registers requires writing the
	 * register address to I23 with XRAE set. When
	 * XRAE is set, I23 changes from an address regis-
	 * ter to a data register. Subsequent accesses to I23
	 * access the extended data register. To convert I23
	 * back to the extended address register, R0 must
	 * be written which internally clears XRAE. As-
	 * suming the part is in MODE 3, the following
	 * steps access the X registers:
	 * 1. Write 17h to R0 (to access I23).
	 * R1 is now the extended address register.
	 * 2. Write the desired X register address to R1
	 * with XRAE = 1.
	 * R1 is now the extended data register.
	 * 3. Write/Read X register data from R1.
	 * To read/write a different X register:
	 * 4. Write 17h to R0 again. (resets XRAE)
	 * R1 is now the extended address register.
	 * 5. Write the new X register address to R1
	 * with XRAE = 1.
	 * R1 is now the new extended data register.
	 * 6. Read/Write new X register data from R1.
	 * */
	unsigned char i23_address = 0x17;
	unsigned char xa3_xa0 = extended_register_address & 0xf0;
	unsigned char xa4 = extended_register_address & 0x04;
	unsigned char xrae = extended_register_address & 0x08;
	unsigned char xa4_xa0 = xa4 << 2 | xa3_xa0 >> 4;
	/* I'm wondering what happens to TRD... TRD can change and is documented as:
	 * Transfer Request Disable: This bit,
	 * when set, causes DMA transfers to
	 * cease when the INT bit of the Status
	 * Register (R2) is set. Independent for
	 * playback and capture interrupts.
	 * For now, sound works on my 560z so I didn't investigate further. */
	wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | i23_address);
	wss_outb(chip, CS4231P(REG),
			extended_register_address | (chip->image[CS4236_EXT_REG] & 0x01));
	wss_outb(chip, CS4231P(REG), new_value);
	chip->eimage[CS4236_REG(extended_register_address)] = new_value;
}
EXPORT_SYMBOL(snd_cs4236_ext_out);

/* Read the extended register. */
unsigned char snd_cs4236_ext_in(struct snd_wss *chip, unsigned char extended_register_address)
{
	unsigned char res;
	unsigned char i23_address = 0x17;
	unsigned char xa3_xa0 = extended_register_address & 0xf0;
	unsigned char xa4 = extended_register_address & 0x04;
	unsigned char xrae = extended_register_address & 0x08;
	unsigned char xa4_xa0 = xa4 << 2 | xa3_xa0 >> 4;
	wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | i23_address);
	wss_outb(chip, CS4231P(REG),
			extended_register_address | (chip->image[CS4236_EXT_REG] & 0x01));
	return wss_inb(chip, CS4231P(REG));
}
EXPORT_SYMBOL(snd_cs4236_ext_in);


/*
 *  CS4231 detection / MCE routines
 */

/* This looks like it is doing 2 things:
 * 1. busy wait
 * 2. "cleanup sequence" which could mean waiting for the register to have good values again? */
static void snd_wss_busy_wait(struct snd_wss *chip)
{
	int timeout;

	/* huh.. looks like this sequence is proper for CS4231A chip (GUS MAX) */
	for (timeout = 5; timeout > 0; timeout--)
		wss_inb(chip, CS4231P(REGSEL));
	/* end of cleanup sequence */
	for (timeout = 25000;
	     timeout > 0 && (wss_inb(chip, CS4231P(REGSEL)) & CS4231_INIT);
	     timeout--)
		udelay(10);
}

/* Mode Change Enable Up: required before changing indirect registers:
 * - Data Format (I8, I28)
 * - Interface Configuration (I9) */
void snd_wss_mce_up(struct snd_wss *chip)
{
	unsigned char index_address_register, cannot_respond, set_mce;
	bool is_mce_set;

	snd_wss_wait(chip);
	guard(spinlock_irqsave)(&chip->reg_lock);
	chip->mce_bit |= CS4231_MCE;
	index_address_register = wss_inb(chip, CS4231P(REGSEL));
	timeout = wss_inb(chip, CS4231P(REGSEL));
	set_mce = CS4231_MCE | (index_address_register & WSS_IA01234_MASK); 
	is_mce_set = (index_address_register & CS4231_MCE) != 0;
	cannot_respond = index_address_register & CS4231_INIT;
	if (!is_mce_set && !cannot_respond)
		/* chip->mce was originally an int, which is strange bceause its name has "bit" so it should
		 * be a single bit. Since we use it to prepare the value to set on the indirect_address_register
		 * I'm not sure what happens to TRD. I need to figure out the value of TRD. If all writes to chip->mce_bit
		 * are also considering the TRD bit, then TRD would be fine, but if not, then TRD would randomly change
		 * value... Since TRD controls DMA transfers, it looks like it could impact playback and capture.
		 * It works for now on my 560z so I haven't investigated further. */
		wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | set_mce);
}
EXPORT_SYMBOL(snd_wss_mce_up);

/* Mode Change Enable Down: locks the indirect registers.  */
void snd_wss_mce_down(struct snd_wss *chip)
{
	unsigned long end_time;
	unsigned char index_address_register, i0, i11;
	bool is_mce_set, is_aci_cleared=true, is_init_cleared=true;

	snd_wss_busy_wait(chip);

	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		chip->mce_bit &= ~CS4231_MCE;
		index_address_register = wss_inb(chip, CS4231P(REGSEL));
		/* Same as for snd_wss_mce_up; what's happening with the TRD bit here? */
		wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | (index_address_register & WSS_IA01234_MASK));
	}
	is_mce_set = (index_address_register & CS4231_MCE) != 0;
	/* There was an hardware check here before. I removed it because snd_wss_mce_up doesn't have that check.
	 * So if we can set the mce up, I think we should be able to set it down. */
	if (!is_mce_set)
		return;

	/*
	 * Wait for (possible -- during init auto-calibration may not be set)
	 * calibration process to start. Needs up to 5 sample periods on AD1848
	 * which at the slowest possible rate of 5.5125 kHz means 907 us.
	 */
	msleep(1);

	/* check condition up to 250 ms */
	end_time = jiffies + msecs_to_jiffies(250);
	/* CS4231_TEST_INIT is 0b0000 1011 which is 11 in decimal. This should be selecting I11 where ACI is. 
	 * CS4231_CALIB_IN_PROGRESS is 0b0010 0000 and that's the ACI (Auto-Calibrate In Progess) bit.
	 * 0 - Calibration not in progress
	 * 1 - Calibration is in progress */
	i11 = snd_wss_in(chip, CS4231_TEST_INIT);
	while (i11 & CS4231_CALIB_IN_PROGRESS) {
		if (time_after(jiffies, end_time)) {
			is_aci_cleared=false;
			break;
		}
		msleep(1);
		i11 = snd_wss_in(chip, CS4231_TEST_INIT);
	}

	/* check condition up to 100 ms */
	end_time = jiffies + msecs_to_jiffies(100);
	/* Read from WSS I0 */
	i0 = wss_inb(chip, CS4231P(REGSEL));
	/* CS4231_INIT which is 0b1000 0000 
	 * INIT - This bit is read as 1 when the Codec is in a state in which it cannot respond to
	 * parallel interface cycles.*/
	while (i0 & CS4231_INIT) {
	while (wss_inb(chip, CS4231P(REGSEL)) & CS4231_INIT) {
		if (time_after(jiffies, end_time)) {
			is_init_cleared=false;
			break;
		}
		msleep(1);
		i0 = wss_inb(chip, CS4231P(REGSEL));
	}

	if (!is_init_cleared || !is_aci_cleared) {
		dev_err(chip->card->dev,
				"is_init_cleared=%d,is_aci_cleared=%d,I0=0x%x,I11=0x%x\n",
				is_init_cleared, is_aci_cleared, i0, i11);
	}
}
EXPORT_SYMBOL(snd_wss_mce_down);

/* Get the count of reads for the DMA so that the DACs will have the right data for playback. */
static unsigned int snd_wss_get_count(unsigned char format, unsigned int size)
{
	unsigned char format_mask = 0b11100000;
/*
 * From the CS4237B datasheet, in I8 (Fs and Playback Data Format Index Register)
 * 
 * +------+------+------+-----------------------------------------------------+
 * | FMT1 | FMT0 | C/L  | Audio Data Format                                   |
 * | (D7) | (D6) | (D5) |                                                     |
 * +------+------+------+-----------------------------------------------------+
 * |  0   |  0   |  0   | Linear, 8-bit unsigned                              |
 * |  0   |  0   |  1   | μ-Law, 8-bit companded                              |
 * |  0   |  1   |  0   | Linear, 16-bit two's complement, Little Endian      |
 * |  0   |  1   |  1   | A-Law, 8-bit companded                              |
 * |  1   |  0   |  0   | RESERVED                                            |
 * |  1   |  0   |  1   | ADPCM, 4-bit, IMA compatible                        |
 * |  1   |  1   |  0   | Linear, 16-bit two's complement, Big Endian         |
 * |  1   |  1   |  1   | RESERVED                                            |
 * +------+------+------+-----------------------------------------------------+
 */
	switch (format & format_mask) {
		case CS4231_LINEAR_16:
		case CS4231_LINEAR_16_BIG:
			size >>= 1;
			break;
		case CS4231_ADPCM_16:
			return size >> 2;
	}
	if (format & CS4231_STEREO)
		size >>= 1;
	return size;
}

static int snd_wss_trigger(struct snd_pcm_substream *substream,
			   int cmd)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	int result = 0;
	unsigned int what;
	struct snd_pcm_substream *s;
	int do_start;

	switch (cmd) {
	case SNDRV_PCM_TRIGGER_START:
	case SNDRV_PCM_TRIGGER_RESUME:
		do_start = 1; break;
	case SNDRV_PCM_TRIGGER_STOP:
	case SNDRV_PCM_TRIGGER_SUSPEND:
		do_start = 0; break;
	default:
		return -EINVAL;
	}

	what = 0;
	snd_pcm_group_for_each_entry(s, substream) {
		if (s == chip->playback_substream) {
			what |= CS4231_PLAYBACK_ENABLE;
			snd_pcm_trigger_done(s, substream);
		} else if (s == chip->capture_substream) {
			what |= CS4231_RECORD_ENABLE;
			snd_pcm_trigger_done(s, substream);
		}
	}
	guard(spinlock)(&chip->reg_lock);
	if (do_start) {
		chip->image[CS4231_IFACE_CTRL] |= what;
		if (chip->trigger)
			chip->trigger(chip, what, 1);
	} else {
		chip->image[CS4231_IFACE_CTRL] &= ~what;
		if (chip->trigger)
			chip->trigger(chip, what, 0);
	}
	snd_wss_out(chip, CS4231_IFACE_CTRL, chip->image[CS4231_IFACE_CTRL]);
	return result;
}

/*
 *  CODEC I/O
 */

static unsigned char snd_wss_get_rate(unsigned int rate)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(rates); i++)
		if (rate == rates[i])
			return freq_bits[i];
	// snd_BUG();
	return freq_bits[ARRAY_SIZE(rates) - 1];
}

static unsigned char snd_wss_get_format(struct snd_wss *chip,
					snd_pcm_format_t format,
					int channels)
{
	unsigned char rformat;

	rformat = CS4231_LINEAR_8;
	switch (format) {
	case SNDRV_PCM_FORMAT_MU_LAW:	rformat = CS4231_ULAW_8; break;
	case SNDRV_PCM_FORMAT_A_LAW:	rformat = CS4231_ALAW_8; break;
	case SNDRV_PCM_FORMAT_S16_LE:	rformat = CS4231_LINEAR_16; break;
	case SNDRV_PCM_FORMAT_S16_BE:	rformat = CS4231_LINEAR_16_BIG; break;
	case SNDRV_PCM_FORMAT_IMA_ADPCM:	rformat = CS4231_ADPCM_16; break;
	}
	if (channels > 1)
		rformat |= CS4231_STEREO;
	return rformat;
}

static void snd_wss_calibrate_mute(struct snd_wss *chip, int mute)
{

	mute = mute ? 0x80 : 0;
	guard(spinlock_irqsave)(&chip->reg_lock);
	if (chip->calibrate_mute == mute)
		return;
	if (!mute) {
		snd_wss_dout(chip, CS4231_LEFT_INPUT,
			     chip->image[CS4231_LEFT_INPUT]);
		snd_wss_dout(chip, CS4231_RIGHT_INPUT,
			     chip->image[CS4231_RIGHT_INPUT]);
		snd_wss_dout(chip, CS4231_LOOPBACK,
			     chip->image[CS4231_LOOPBACK]);
	} else {
		snd_wss_dout(chip, CS4231_LEFT_INPUT,
			     0);
		snd_wss_dout(chip, CS4231_RIGHT_INPUT,
			     0);
		snd_wss_dout(chip, CS4231_LOOPBACK,
			     0xfd);
	}

	snd_wss_dout(chip, CS4231_AUX1_LEFT_INPUT,
		     mute | chip->image[CS4231_AUX1_LEFT_INPUT]);
	snd_wss_dout(chip, CS4231_AUX1_RIGHT_INPUT,
		     mute | chip->image[CS4231_AUX1_RIGHT_INPUT]);
	snd_wss_dout(chip, CS4231_AUX2_LEFT_INPUT,
		     mute | chip->image[CS4231_AUX2_LEFT_INPUT]);
	snd_wss_dout(chip, CS4231_AUX2_RIGHT_INPUT,
		     mute | chip->image[CS4231_AUX2_RIGHT_INPUT]);
	snd_wss_dout(chip, CS4231_LEFT_OUTPUT,
		     mute | chip->image[CS4231_LEFT_OUTPUT]);
	snd_wss_dout(chip, CS4231_RIGHT_OUTPUT,
		     mute | chip->image[CS4231_RIGHT_OUTPUT]);
	/* simplfied code since hardware is WSS_HW_CS4237B */
	chip->calibrate_mute = mute;
}

/* Check the 3 format bits, store them in chip->image[CS4231_PLAYBK_FORMAT] and write them out on the WSS registers. */
static void snd_wss_playback_format(struct snd_wss *chip,
				       struct snd_pcm_hw_params *params,
				       unsigned char pdfr)
{
	/* Fs and Playback Data Format (I8)
	 * D7   D6   D5  D4  D3   D2   D1   D0
	 * FMT1 FMT0 C/L S/M CFS2 CFS1 CFS0 C2SL */
	/* Alternate Feature Enable I (I16)
	 * D4
	 * PMCE
	 * Playback Mode Change Enable.
	 * When set, it allows modification of
	 * the stereo/mono and audio data for-
	 * mat bits (D7-D4) for the playback
	 * channel, I8. MCE in R0 must be
	 * used to change the sample fre-
	 * quency. */
	/* snd_wss_create calls snd_wss_probe which sets the chip_hardware to WSS_HW_CS4237B 
	 * I believe it's unlikely that the hardware changes afterwards and also very likely 
	 * that snd_wss_playback_format is only called after the snd_wss_probe. 
	 * I removed code which was checking for other versions than the CS4237B. */

	guard(mutex)(&chip->mce_mutex);
	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		chip->image[CS4231_PLAYBK_FORMAT] = pdfr;
		snd_wss_out(chip, CS4231_PLAYBK_FORMAT, pdfr);
	}
	snd_wss_mce_down(chip);
}

/* set the capture format on 
 * CS4231_PLAYBK_FORMAT which is 0x08 which is I8
 * Fs and Playback Data Format (I8)
 * Default = 00000000
 * D7 D6 D5 D4 D3 D2 D1 D0
 * FMT1 FMT0 C/L S/M CFS2 CFS1 CFS0 C2SL
 * CS4131_REC_FORMAT which ix 0x1c which is I28.
 * Capture Data Format (I28)
 * Default = 0000xxxx
 * D7 D6 D5 D4 D3 D2 D1 D0
 * FMT1 FMT0 C/L S/M res res res res */
static void snd_wss_capture_format(struct snd_wss *chip,
				   struct snd_pcm_hw_params *params,
				   unsigned char cdfr)
{
	unsigned long flags;

	guard(mutex)(&chip->mce_mutex);
	snd_wss_mce_up(chip);
	spin_lock_irqsave(&chip->reg_lock, flags);
	/* TODO tres etrange. Je pense que ce if ne devrait pas s'appliquer. Peut-etre le garder et mettre en dbg_err 
	 * pour le suivre a l'execution. Vu que le son fonctionne, je n'ai pas poursuivi mes recherches. */
	if (!(chip->image[CS4231_IFACE_CTRL] & CS4231_PLAYBACK_ENABLE)) {
		snd_wss_out(chip, CS4231_PLAYBK_FORMAT,
			(chip->image[CS4231_PLAYBK_FORMAT] & 0xf0) |
			(cdfr & 0x0f));
		spin_unlock_irqrestore(&chip->reg_lock, flags);
		snd_wss_mce_down(chip);
		snd_wss_mce_up(chip);
		spin_lock_irqsave(&chip->reg_lock, flags);
	}
	/* TODO etrange qu'on ne sauvegarde pas le cdfr and chip->image[CS4231_REC_FORMAT].
	 * aussi, est-ce qu'on doit faire quelque chose avec chip->image[CS4231_ALT_FEATURE_1] &= 0x20 ...
	 * Le son fonctionne sur mon 560z, je n,ai pas poursuivi mes recherches. */
	/* chip->hardware is WSS_HW_CS4237B which is 0x0402 
	 * WSS_HW_AD1848_MASK is 0x0800 so I can remove the if and keep the else. */
	snd_wss_out(chip, CS4231_REC_FORMAT, cdfr);
	spin_unlock_irqrestore(&chip->reg_lock, flags);
	snd_wss_mce_down(chip);
}

/*
 *  Timer interface
 */

static unsigned long snd_wss_timer_resolution(struct snd_timer *timer)
{
	struct snd_wss *chip = snd_timer_chip(timer);
	if (chip->hardware & WSS_HW_CS4236B_MASK)
		return 14467;
	else
		return chip->image[CS4231_PLAYBK_FORMAT] & 1 ? 9969 : 9920;
}

static int snd_wss_timer_start(struct snd_timer *timer)
{
	unsigned int ticks;
	struct snd_wss *chip = snd_timer_chip(timer);

	guard(spinlock_irqsave)(&chip->reg_lock);
	ticks = timer->sticks;
	if ((chip->image[CS4231_ALT_FEATURE_1] & CS4231_TIMER_ENABLE) == 0 ||
	    (unsigned char)(ticks >> 8) != chip->image[CS4231_TIMER_HIGH] ||
	    (unsigned char)ticks != chip->image[CS4231_TIMER_LOW]) {
		chip->image[CS4231_TIMER_HIGH] = (unsigned char) (ticks >> 8);
		snd_wss_out(chip, CS4231_TIMER_HIGH,
			    chip->image[CS4231_TIMER_HIGH]);
		chip->image[CS4231_TIMER_LOW] = (unsigned char) ticks;
		snd_wss_out(chip, CS4231_TIMER_LOW,
			    chip->image[CS4231_TIMER_LOW]);
		snd_wss_out(chip, CS4231_ALT_FEATURE_1,
			    chip->image[CS4231_ALT_FEATURE_1] |
			    CS4231_TIMER_ENABLE);
	}
	return 0;
}

static int snd_wss_timer_stop(struct snd_timer *timer)
{
	struct snd_wss *chip = snd_timer_chip(timer);

	guard(spinlock_irqsave)(&chip->reg_lock);
	chip->image[CS4231_ALT_FEATURE_1] &= ~CS4231_TIMER_ENABLE;
	snd_wss_out(chip, CS4231_ALT_FEATURE_1,
		    chip->image[CS4231_ALT_FEATURE_1]);
	return 0;
}

static void snd_wss_init(struct snd_wss *chip)
{
	snd_wss_calibrate_mute(chip, 1);
	snd_wss_mce_down(chip);

	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		chip->image[CS4231_IFACE_CTRL] &= ~(CS4231_PLAYBACK_ENABLE |
						    CS4231_PLAYBACK_PIO |
						    CS4231_RECORD_ENABLE |
						    CS4231_RECORD_PIO |
						    CS4231_CALIB_MODE);
		chip->image[CS4231_IFACE_CTRL] |= CS4231_AUTOCALIB;
		snd_wss_out(chip, CS4231_IFACE_CTRL, chip->image[CS4231_IFACE_CTRL]);
	}
	snd_wss_mce_down(chip);

	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		chip->image[CS4231_IFACE_CTRL] &= ~CS4231_AUTOCALIB;
		snd_wss_out(chip, CS4231_IFACE_CTRL, chip->image[CS4231_IFACE_CTRL]);
		snd_wss_out(chip,
			    CS4231_ALT_FEATURE_1, chip->image[CS4231_ALT_FEATURE_1]);
	}
	snd_wss_mce_down(chip);

	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		snd_wss_out(chip, CS4231_ALT_FEATURE_2,
			    chip->image[CS4231_ALT_FEATURE_2]);
	}

	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		snd_wss_out(chip, CS4231_PLAYBK_FORMAT,
			    chip->image[CS4231_PLAYBK_FORMAT]);
	}
	snd_wss_mce_down(chip);

	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		if (!(chip->hardware & WSS_HW_AD1848_MASK))
			snd_wss_out(chip, CS4231_REC_FORMAT,
				    chip->image[CS4231_REC_FORMAT]);
	}
	snd_wss_mce_down(chip);
	snd_wss_calibrate_mute(chip, 0);
}

static int snd_wss_open(struct snd_wss *chip, unsigned int mode)
{
	guard(mutex)(&chip->open_mutex);
	if (chip->mode & mode)
		return -EAGAIN;
	if (chip->mode & WSS_MODE_OPEN) {
		chip->mode |= mode;
		return 0;
	}
	/* ok. now enable and ack CODEC IRQ */
	guard(spinlock_irqsave)(&chip->reg_lock);
	if (!(chip->hardware & WSS_HW_AD1848_MASK)) {
		snd_wss_out(chip, CS4231_IRQ_STATUS,
			    CS4231_PLAYBACK_IRQ |
			    CS4231_RECORD_IRQ |
			    CS4231_TIMER_IRQ);
		snd_wss_out(chip, CS4231_IRQ_STATUS, 0);
	}
	wss_outb(chip, CS4231P(STATUS), 0);	/* clear IRQ */
	wss_outb(chip, CS4231P(STATUS), 0);	/* clear IRQ */
	chip->image[CS4231_PIN_CTRL] |= CS4231_IRQ_ENABLE;
	snd_wss_out(chip, CS4231_PIN_CTRL, chip->image[CS4231_PIN_CTRL]);
	if (!(chip->hardware & WSS_HW_AD1848_MASK)) {
		snd_wss_out(chip, CS4231_IRQ_STATUS,
			    CS4231_PLAYBACK_IRQ |
			    CS4231_RECORD_IRQ |
			    CS4231_TIMER_IRQ);
		snd_wss_out(chip, CS4231_IRQ_STATUS, 0);
	}

	chip->mode = mode;
	return 0;
}

static void snd_wss_close(struct snd_wss *chip, unsigned int mode)
{
	unsigned long flags;

	guard(mutex)(&chip->open_mutex);
	chip->mode &= ~mode;
	if (chip->mode & WSS_MODE_OPEN)
		return;
	/* disable IRQ */
	spin_lock_irqsave(&chip->reg_lock, flags);
	if (!(chip->hardware & WSS_HW_AD1848_MASK))
		snd_wss_out(chip, CS4231_IRQ_STATUS, 0);
	wss_outb(chip, CS4231P(STATUS), 0);	/* clear IRQ */
	wss_outb(chip, CS4231P(STATUS), 0);	/* clear IRQ */
	chip->image[CS4231_PIN_CTRL] &= ~CS4231_IRQ_ENABLE;
	snd_wss_out(chip, CS4231_PIN_CTRL, chip->image[CS4231_PIN_CTRL]);

	/* now disable record & playback */

	if (chip->image[CS4231_IFACE_CTRL] & (CS4231_PLAYBACK_ENABLE | CS4231_PLAYBACK_PIO |
					       CS4231_RECORD_ENABLE | CS4231_RECORD_PIO)) {
		spin_unlock_irqrestore(&chip->reg_lock, flags);
		snd_wss_mce_up(chip);
		spin_lock_irqsave(&chip->reg_lock, flags);
		chip->image[CS4231_IFACE_CTRL] &= ~(CS4231_PLAYBACK_ENABLE | CS4231_PLAYBACK_PIO |
						     CS4231_RECORD_ENABLE | CS4231_RECORD_PIO);
		snd_wss_out(chip, CS4231_IFACE_CTRL,
			    chip->image[CS4231_IFACE_CTRL]);
		spin_unlock_irqrestore(&chip->reg_lock, flags);
		snd_wss_mce_down(chip);
		spin_lock_irqsave(&chip->reg_lock, flags);
	}

	/* clear IRQ again */
	if (!(chip->hardware & WSS_HW_AD1848_MASK))
		snd_wss_out(chip, CS4231_IRQ_STATUS, 0);
	wss_outb(chip, CS4231P(STATUS), 0);	/* clear IRQ */
	wss_outb(chip, CS4231P(STATUS), 0);	/* clear IRQ */
	spin_unlock_irqrestore(&chip->reg_lock, flags);

	chip->mode = 0;
}

/*
 *  timer open/close
 */

static int snd_wss_timer_open(struct snd_timer *timer)
{
	struct snd_wss *chip = snd_timer_chip(timer);
	snd_wss_open(chip, WSS_MODE_TIMER);
	return 0;
}

static int snd_wss_timer_close(struct snd_timer *timer)
{
	struct snd_wss *chip = snd_timer_chip(timer);
	snd_wss_close(chip, WSS_MODE_TIMER);
	return 0;
}

static const struct snd_timer_hardware snd_wss_timer_table =
{
	.flags =	SNDRV_TIMER_HW_AUTO,
	.resolution =	9945,
	.ticks =	65535,
	.open =		snd_wss_timer_open,
	.close =	snd_wss_timer_close,
	.c_resolution = snd_wss_timer_resolution,
	.start =	snd_wss_timer_start,
	.stop =		snd_wss_timer_stop,
};

/*
 *  ok.. exported functions..
 */

static int snd_wss_playback_hw_params(struct snd_pcm_substream *substream,
					 struct snd_pcm_hw_params *hw_params)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	unsigned char new_pdfr;

	new_pdfr = snd_wss_get_format(chip, params_format(hw_params),
				params_channels(hw_params)) |
				snd_wss_get_rate(params_rate(hw_params));
	chip->set_playback_format(chip, hw_params, new_pdfr);
	return 0;
}

/* Set the playback DMA registers for sending data to the DACs.
 * PLAYBACK DMA REGISTERS
 * The playback DMA registers (I14/15) are used
 * for sending playback data to the DACs in
 * MODE 2 and 3. In MODE 1, these registers
 * (I14/15) are used for both playback and capture;
 * therefore, full-duplex DMA operation is not pos-
 * sible.
 * When the playback Current Count register rolls
 * under, the Playback Interrupt bit, PI, (I24) is set
 * causing the INT bit (R2) to be set. The interrupt
 * is cleared by a write of any value to the Status
 * register (R2), or writing a "0" to the Playback
 * Interrupt bit, PI (I24).
 * We should be in MODE 2 since MODE 2, forces the part to
 * appear as a CS4231 super set and is compatible
 * with the CS4232. */
static int snd_wss_playback_prepare(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	struct snd_pcm_runtime *runtime = substream->runtime;
	unsigned int size = snd_pcm_lib_buffer_bytes(substream);
	unsigned int count = snd_pcm_lib_period_bytes(substream);

	guard(spinlock_irqsave)(&chip->reg_lock);
	chip->p_dma_size = size;
	chip->image[CS4231_IFACE_CTRL] &= ~(CS4231_PLAYBACK_ENABLE | CS4231_PLAYBACK_PIO);
	snd_dma_program(chip->dma1, runtime->dma_addr, size, DMA_MODE_WRITE | DMA_AUTOINIT);
	/* By claude.ai:
	 * The -1 in the count = snd_wss_get_count(chip->image[CS4231_PLAYBK_FORMAT], count) - 1; line is due to how DMA controllers typically work with count registers.
	 * In many DMA controllers, including those used with the CS4231/CS4237B chips, the count value is loaded as "number of transfers minus 1" because:
	 *
	 * The DMA controller will execute (count+1) transfers before generating an interrupt
	 * A value of 0 in the count register typically means "execute 1 transfer" not "execute 0 transfers"
	 * This allows for the maximum possible range of the counter (e.g., a 16-bit counter can represent 1 to 65,536 transfers, not 0 to 65,535)
	 *
	 * So in the context of this code:
	 *
	 * snd_wss_get_count() calculates how many samples are in the period
	 * The -1 adjusts this to the "N-1" format expected by the DMA hardware
	 * The value is then split into lower and upper bytes and written to the DMA count registers
	 *
	 * This is a common pattern in hardware programming where registers follow the "N-1" encoding scheme for counters.
	 * */
	count = snd_wss_get_count(chip->image[CS4231_PLAYBK_FORMAT], count) - 1;
	/* CS4231_PLY_LWR_CNT is 0b0000 1111 
	 * Playback Lower Base (I15)
	 * Lower Base Bits: This register is the
	 * lower byte which represents the 8
	 * least significant bits of the 16-bit
	 * Playback Base register. Reads from
	 * this register return the same value
	 * which was written. When set for
	 * MODE 1 or SDC, this register is
	 * used for both the Playback and Cap-
	 * ture Base registers.*/
	snd_wss_out(chip, CS4231_PLY_LWR_CNT, (unsigned char) count);
	/* CS4231_PLY_UPR_CNT is 0b0000 1110 
	 * Playback Upper Base (I14)
	 * Playback Upper Base: This register is
	 * the upper byte which represents the
	 * 8 most significant bits of the 16-bit
	 * Playback Base register. Reads from
	 * this register return the same value
	 * which was written. The Current
	 * Count registers cannot be read.
	 * When set for MODE 1 or SDC, this
	 * register is used for both the Play-
	 * back and Capture Base registers.
	 * */
	snd_wss_out(chip, CS4231_PLY_UPR_CNT, (unsigned char) (count >> 8));
	return 0;
}

static int snd_wss_capture_hw_params(struct snd_pcm_substream *substream,
					struct snd_pcm_hw_params *hw_params)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	unsigned char new_cdfr;

	new_cdfr = snd_wss_get_format(chip, params_format(hw_params),
			   params_channels(hw_params)) |
			   snd_wss_get_rate(params_rate(hw_params));
	chip->set_capture_format(chip, hw_params, new_cdfr);
	return 0;
}

static int snd_wss_capture_prepare(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	struct snd_pcm_runtime *runtime = substream->runtime;
	unsigned int size = snd_pcm_lib_buffer_bytes(substream);
	unsigned int count = snd_pcm_lib_period_bytes(substream);

	guard(spinlock_irqsave)(&chip->reg_lock);
	chip->c_dma_size = size;
	chip->image[CS4231_IFACE_CTRL] &= ~(CS4231_RECORD_ENABLE | CS4231_RECORD_PIO);
	snd_dma_program(chip->dma2, runtime->dma_addr, size, DMA_MODE_READ | DMA_AUTOINIT);
	/* 560z is a CS4237B. simplifying */
	/* the -1 is because sending a count of 0 will result in a DMA transfer so if
	 * the count is 1 for 1 read, we need to send 0 */
	count = snd_wss_get_count(chip->image[CS4231_REC_FORMAT],
			count);
	count--;
	/* 560z is a 2 dma. simplifying*/
	snd_wss_out(chip, CS4231_REC_LWR_CNT, (unsigned char) count);
	snd_wss_out(chip, CS4231_REC_UPR_CNT,
		(unsigned char) (count >> 8));
	return 0;
}

void snd_wss_overrange(struct snd_wss *chip)
{
	unsigned char res;

	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		res = snd_wss_in(chip, CS4231_TEST_INIT);
	}
	if (res & (0x08 | 0x02))	/* detect overrange only above 0dB; may be user selectable? */
		chip->capture_substream->runtime->overrange++;
}
EXPORT_SYMBOL(snd_wss_overrange);

/* I think this handles interrupts duing playback and capture.
 * TODO figure out what snd_pcm_period_elapsed does. Since the sound
 * works, I didn't investigate further. */
irqreturn_t snd_wss_interrupt(int irq, void *dev_id)
{
	struct snd_wss *chip = dev_id;
	unsigned char status;

	/* 560z is a CS4237B. simplifying */
	status = snd_wss_in(chip, CS4231_IRQ_STATUS);
	if (status & CS4231_TIMER_IRQ) {
		if (chip->timer)
			snd_timer_interrupt(chip->timer, chip->timer->sticks);
	}
	/* 560z is a 2 dma. simplifying*/
	if (status & CS4231_PLAYBACK_IRQ) {
		if (chip->playback_substream)
			snd_pcm_period_elapsed(chip->playback_substream);
	}
	if (status & CS4231_RECORD_IRQ) {
		if (chip->capture_substream) {
			snd_wss_overrange(chip);
			snd_pcm_period_elapsed(chip->capture_substream);
		}
	}

	guard(spinlock)(&chip->reg_lock);
	status = ~CS4231_ALL_IRQS | ~status;
	snd_wss_out(chip, CS4231_IRQ_STATUS, status);
	return IRQ_HANDLED;
}
EXPORT_SYMBOL(snd_wss_interrupt);

static snd_pcm_uframes_t snd_wss_playback_pointer(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	size_t ptr;

	if (!(chip->image[CS4231_IFACE_CTRL] & CS4231_PLAYBACK_ENABLE))
		return 0;
	ptr = snd_dma_pointer(chip->dma1, chip->p_dma_size);
	return bytes_to_frames(substream->runtime, ptr);
}

static snd_pcm_uframes_t snd_wss_capture_pointer(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	size_t ptr;

	if (!(chip->image[CS4231_IFACE_CTRL] & CS4231_RECORD_ENABLE))
		return 0;
	ptr = snd_dma_pointer(chip->dma2, chip->c_dma_size);
	return bytes_to_frames(substream->runtime, ptr);
}

/* probe the card and fill information such as hardware.
 * For my 560z, chip->hardware is WSS_HW_CS4237B */
static int snd_wss_probe(struct snd_wss *chip)
{
	int i, id, rev, regnum;
	unsigned char *ptr;
	unsigned int hw;

	hw = chip->hardware;
	/* Below is a bit difficult to understand because I heavily modified the code
	 * and hard-coded values which I know from testing do work with the 560z. */
	/* I kept only down here from the "if ((hw & WSS_HW_TYPE_MASK) == WSS_HW_DETECT)" code block */
	/* scoped_guard was added when I rewrote for 6.18.8
	 * it was only a guard within a scope, but since I'm hard-coding values, I needed
	 * a scoped guard. */
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		/* CS4231_MISC_INFO is 0x0c so I12
		 * MODE and ID (I12)
		 * Default = 100x1010
		 * D7 D6 D5 D4 D3 D2 D1 D0
		 * 1 CMS1 CMS0 res ID3 ID2 ID1 ID0
		 * CMS1,0 Codec Mode Select bits: Enables the
		 * Extended registers and functions of
		 * the part.
		 * 00 - MODE 1
		 * 01 - Reserved
		 * 10 - MODE 2
		 * 11 - MODE 3 */
		/* CS4231_4236_MODE3 is 0xe0 so 0b1110 0000 */
		/* Previous patch had this mb after the -ENODEV
		 * but the only mb in the code block I replaced was before
		 * the snd_wss_out. It makes more sense here, */
	  mb();
		snd_wss_out(chip, CS4231_MISC_INFO, CS4231_4236_MODE3);
		id = snd_wss_in(chip, CS4231_MISC_INFO) & 0x0f;
	}
	/* This is port = 0x530, id = 0xa for my IBM 560z */
	dev_dbg(chip->card->dev, "wss: port = 0x%lx, id = 0x%x\n", chip->port, id);
	if (id != 0x0a) {
		dev_err(chip->card->dev, "invalid device with id 0x%x\n", id);
		return -ENODEV;	/* no valid device found */
	}

	rev = snd_wss_in(chip, CS4231_VERSION) & 0xe7;
	/* This is 0x3 for my IBM 560z
	 * Compatibility ID (I25)
	 * Default = 00000011
	 * D7 D6 D5 D4 D3 D2 D1 D0
	 * V2 V1 V0 CID4 CID3 CID2 CID1 CID0
	 * CID4-CID0 00011 - CS4236, CS4237B */
	dev_dbg(chip->card->dev, "CS4231: VERSION (I25) = 0x%x\n", rev);
	if (rev != 0x03) {
		dev_err(chip->card->dev, "not the 560z and not the CS4237B because version 0x%x\n", rev);
		return -ENODEV;
	}
	/* I kept only up here from the "if ((hw & WSS_HW_TYPE_MASK) == WSS_HW_DETECT)" code block */

	/* This block was added when rewriting for 6.18.8.
	 * I found it here in the original 6.18.8 code. It was
	 * placed below the next block in my original patch.  */
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		wss_inb(chip, CS4231P(STATUS));	/* clear any pendings IRQ */
		wss_outb(chip, CS4231P(STATUS), 0);
		mb();
	}
	/* This part below I kept, but heavily simplified. The next
	 * comment block comes from the original code and gives an
	 * idea of the original sequence. */
	/* ok.. try check hardware version for CS4236+ chips */
	/* CS4236_VERSION is 0x9c which is 0b1001 1100
	 * Extended Register Access (I23)
	 * D7  D6  D5  D4  D3   D2  D1  D0
	 * XA3 XA2 XA1 XA0 XRAE XA4 res ACF
	 * 1   0   0   1   1    1   0   0
	 * XA4 Extended Register Address bit 4.
	 * Along with XA3-XA0, enables ac-
	 * cess to extended registers X16,
	 * X17, and X25. MODE 3 only.
	 * XA3-XA0
	 * Extended Register Address. Along
	 * with XA4, sets the register number
	 * (X0-X17+X25) accessed when
	 * XRAE is set. MODE 3 only. See the
	 * WSS Extended Register section for
	 * more details.
	 * So XA4 being set, this enables access to X16,X17 and X25
	 * With XA3-XA0 set to 1001 we have 16+9=25. So we read
	 * X25 which is Chip Version and ID.
	 * D7 D6 D5 D4 D3 D2 D1 D0
	 * V2 V1 V0 CID4 CID3 CID2 CID1 CID0
	 * my 560z reads 0xe8
	 * e - 1110 - V2-V0 are 111 - 111 - Revision E
	 * 8 - 1000 - CID4-CID0 are 01000 - 01000 - CS4237B*/
	/* rev is 0xe8*/
	rev = snd_cs4236_ext_in(chip, CS4236_VERSION);
	if ((rev & 0x1f) == 0x08) {	/* CS4237B */
		chip->hardware = WSS_HW_CS4237B;
		switch (rev >> 5) {
			case 0:
			case 6:
			case 7:
				break;
			default:
				dev_err(chip->card->dev, "unknown CS4237B chip (enhanced version = 0x%x)\n", id);
				/* I added this after porting the code changes to 4.4.302 since it would be best to
				 * stop the probe instead of continuing with a result that might be broken. */
				return -ENODEV;
		}
	}
	else {
		dev_err(chip->card->dev, "unknown CS4236/CS423xB chip (enhanced version = 0x%x)\n", id);
		/* I added this after porting the code changes to 4.4.302 since it would be best to
		 * stop the probe instead of continuing with a result that might be broken. */
		return -ENODEV;
	}


	/* 560z is a CS4237B. simplifying. MODE 3 is like MODE 2 + extended registers */
	chip->image[CS4231_MISC_INFO] = CS4231_4236_MODE3;
	/* 560z is a 2 dma. simplifying*/
	chip->image[CS4231_IFACE_CTRL] = chip->image[CS4231_IFACE_CTRL] & ~CS4231_SINGLE_DMA;
	/* 560z is a CS4237B. simplifying */
	ptr = (unsigned char *) &chip->image;
	/* 560z is a CS4237B. simplifying */
	regnum = 32;
	snd_wss_mce_down(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
	/* TODO figure out why we set each indirect register...
	 * From what I have seen, this is not entirely needed. We could skip
	 * a number of registers, but since the sound is working now, I didn't
	 * continue the investigation.
	 * Setting the MODE3 on CMS1,0 bits in I12 here. */
		for (i = 0; i < regnum; i++)	/* ok.. fill all registers */
			snd_wss_out(chip, i, *ptr++);
	}
	snd_wss_mce_up(chip);
	snd_wss_mce_down(chip);

	/* TODO can this delay be removed? Sound is working; didn't continue the investigation. */
	mdelay(2);

	return 0;		/* all things are ok.. */
}

/*

 */

static const struct snd_pcm_hardware snd_wss_playback =
{
	.info =			(SNDRV_PCM_INFO_MMAP | SNDRV_PCM_INFO_INTERLEAVED |
				 SNDRV_PCM_INFO_MMAP_VALID |
				 SNDRV_PCM_INFO_SYNC_START),
	.formats =		(SNDRV_PCM_FMTBIT_MU_LAW | SNDRV_PCM_FMTBIT_A_LAW | SNDRV_PCM_FMTBIT_IMA_ADPCM |
				 SNDRV_PCM_FMTBIT_U8 | SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S16_BE),
	.rates =		SNDRV_PCM_RATE_KNOT | SNDRV_PCM_RATE_8000_48000,
	.rate_min =		5510,
	.rate_max =		48000,
	.channels_min =		1,
	.channels_max =		2,
	.buffer_bytes_max =	(128*1024),
	.period_bytes_min =	64,
	.period_bytes_max =	(128*1024),
	.periods_min =		1,
	.periods_max =		1024,
	.fifo_size =		0,
};

static const struct snd_pcm_hardware snd_wss_capture =
{
	.info =			(SNDRV_PCM_INFO_MMAP | SNDRV_PCM_INFO_INTERLEAVED |
				 SNDRV_PCM_INFO_MMAP_VALID |
				 SNDRV_PCM_INFO_RESUME |
				 SNDRV_PCM_INFO_SYNC_START),
	.formats =		(SNDRV_PCM_FMTBIT_MU_LAW | SNDRV_PCM_FMTBIT_A_LAW | SNDRV_PCM_FMTBIT_IMA_ADPCM |
				 SNDRV_PCM_FMTBIT_U8 | SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S16_BE),
	.rates =		SNDRV_PCM_RATE_KNOT | SNDRV_PCM_RATE_8000_48000,
	.rate_min =		5510,
	.rate_max =		48000,
	.channels_min =		1,
	.channels_max =		2,
	.buffer_bytes_max =	(128*1024),
	.period_bytes_min =	64,
	.period_bytes_max =	(128*1024),
	.periods_min =		1,
	.periods_max =		1024,
	.fifo_size =		0,
};

/*

 */

static int snd_wss_playback_open(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	struct snd_pcm_runtime *runtime = substream->runtime;
	int err;

	runtime->hw = snd_wss_playback;

	snd_pcm_limit_isa_dma_size(chip->dma1, &runtime->hw.buffer_bytes_max);
	snd_pcm_limit_isa_dma_size(chip->dma1, &runtime->hw.period_bytes_max);

	if (chip->claim_dma) {
		err = chip->claim_dma(chip, chip->dma_private_data, chip->dma1);
		if (err < 0)
			return err;
	}

	err = snd_wss_open(chip, WSS_MODE_PLAY);
	if (err < 0) {
		if (chip->release_dma)
			chip->release_dma(chip, chip->dma_private_data, chip->dma1);
		return err;
	}
	chip->playback_substream = substream;
	snd_pcm_set_sync(substream);
	chip->rate_constraint(runtime);
	return 0;
}

static int snd_wss_capture_open(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);
	struct snd_pcm_runtime *runtime = substream->runtime;
	int err;

	runtime->hw = snd_wss_capture;

	snd_pcm_limit_isa_dma_size(chip->dma2, &runtime->hw.buffer_bytes_max);
	snd_pcm_limit_isa_dma_size(chip->dma2, &runtime->hw.period_bytes_max);

	if (chip->claim_dma) {
		err = chip->claim_dma(chip, chip->dma_private_data, chip->dma2);
		if (err < 0)
			return err;
	}

	err = snd_wss_open(chip, WSS_MODE_RECORD);
	if (err < 0) {
		if (chip->release_dma)
			chip->release_dma(chip, chip->dma_private_data, chip->dma2);
		return err;
	}
	chip->capture_substream = substream;
	snd_pcm_set_sync(substream);
	chip->rate_constraint(runtime);
	return 0;
}

static int snd_wss_playback_close(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);

	chip->playback_substream = NULL;
	snd_wss_close(chip, WSS_MODE_PLAY);
	return 0;
}

static int snd_wss_capture_close(struct snd_pcm_substream *substream)
{
	struct snd_wss *chip = snd_pcm_substream_chip(substream);

	chip->capture_substream = NULL;
	snd_wss_close(chip, WSS_MODE_RECORD);
	return 0;
}


#ifdef CONFIG_PM

/* lowlevel suspend callback for CS4231 */
static void snd_wss_suspend(struct snd_wss *chip)
{
	int reg;

	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		for (reg = 0; reg < 32; reg++)
			chip->image[reg] = snd_wss_in(chip, reg);
	}
	if (chip->thinkpad_flag)
		snd_wss_thinkpad_twiddle(chip, 0);
}

/* lowlevel resume callback for CS4231 */
static void snd_wss_resume(struct snd_wss *chip)
{
	int reg;
	/* int timeout; */

	if (chip->thinkpad_flag)
		snd_wss_thinkpad_twiddle(chip, 1);
	snd_wss_mce_up(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		for (reg = 0; reg < 32; reg++) {
			switch (reg) {
			case CS4231_VERSION:
				break;
			default:
				snd_wss_out(chip, reg, chip->image[reg]);
				break;
			}
		}
		/* Yamaha needs this to resume properly */
		if (chip->hardware == WSS_HW_OPL3SA2)
			snd_wss_out(chip, CS4231_PLAYBK_FORMAT,
				    chip->image[CS4231_PLAYBK_FORMAT]);
	}
#if 1
	snd_wss_mce_down(chip);
#else
	/* The following is a workaround to avoid freeze after resume on TP600E.
	   This is the first half of copy of snd_wss_mce_down(), but doesn't
	   include rescheduling.  -- iwai
	   */
	snd_wss_busy_wait(chip);
	scoped_guard(spinlock_irqsave, &chip->reg_lock) {
		chip->mce_bit &= ~CS4231_MCE;
		timeout = wss_inb(chip, CS4231P(REGSEL));
		wss_outb(chip, CS4231P(REGSEL), chip->mce_bit | (timeout & 0x1f));
	}
	if (timeout == 0x80)
		dev_err(chip->card->dev
			"down [0x%lx]: serious init problem - codec still busy\n",
			chip->port);
	if ((timeout & CS4231_MCE) == 0 ||
	    !(chip->hardware & (WSS_HW_CS4231_MASK | WSS_HW_CS4232_MASK))) {
		return;
	}
	snd_wss_busy_wait(chip);
#endif
}
#endif /* CONFIG_PM */

const char *snd_wss_chip_id(struct snd_wss *chip)
{
	switch (chip->hardware) {
	case WSS_HW_CS4231:
		return "CS4231";
	case WSS_HW_CS4231A:
		return "CS4231A";
	case WSS_HW_CS4232:
		return "CS4232";
	case WSS_HW_CS4232A:
		return "CS4232A";
	case WSS_HW_CS4235:
		return "CS4235";
	case WSS_HW_CS4236:
		return "CS4236";
	case WSS_HW_CS4236B:
		return "CS4236B";
	case WSS_HW_CS4237B:
		return "CS4237B";
	case WSS_HW_CS4238B:
		return "CS4238B";
	case WSS_HW_CS4239:
		return "CS4239";
	case WSS_HW_INTERWAVE:
		return "AMD InterWave";
	case WSS_HW_OPL3SA2:
		return chip->card->shortname;
	case WSS_HW_AD1845:
		return "AD1845";
	case WSS_HW_OPTI93X:
		return "OPTi 93x";
	case WSS_HW_AD1847:
		return "AD1847";
	case WSS_HW_AD1848:
		return "AD1848";
	case WSS_HW_CS4248:
		return "CS4248";
	case WSS_HW_CMI8330:
		return "CMI8330/C3D";
	default:
		return "???";
	}
}
EXPORT_SYMBOL(snd_wss_chip_id);

static int snd_wss_new(struct snd_card *card,
			  unsigned short hardware,
			  unsigned short hwshare,
			  struct snd_wss **rchip)
{
	struct snd_wss *chip;

	*rchip = NULL;
	chip = devm_kzalloc(card->dev, sizeof(*chip), GFP_KERNEL);
	if (chip == NULL)
		return -ENOMEM;
	chip->hardware = hardware;
	chip->hwshare = hwshare;

	spin_lock_init(&chip->reg_lock);
	mutex_init(&chip->mce_mutex);
	mutex_init(&chip->open_mutex);
	chip->card = card;
	chip->rate_constraint = snd_wss_xrate;
	chip->set_playback_format = snd_wss_playback_format;
	chip->set_capture_format = snd_wss_capture_format;
	if (chip->hardware == WSS_HW_OPTI93X)
		memcpy(&chip->image, &snd_opti93x_original_image,
		       sizeof(snd_opti93x_original_image));
	else
		memcpy(&chip->image, &snd_wss_original_image,
		       sizeof(snd_wss_original_image));
	if (chip->hardware & WSS_HW_AD1848_MASK) {
		chip->image[CS4231_PIN_CTRL] = 0;
		chip->image[CS4231_TEST_INIT] = 0;
	}

	*rchip = chip;
	return 0;
}

int snd_wss_create(struct snd_card *card,
		      unsigned long port,
		      int irq, int dma1, int dma2,
		      unsigned short hardware,
		      unsigned short hwshare,
		      struct snd_wss **rchip)
{
	struct snd_wss *chip;
	int err;

	err = snd_wss_new(card, hardware, hwshare, &chip);
	if (err < 0)
		return err;

	chip->irq = -1;
	chip->dma1 = -1;
	chip->dma2 = -1;

	chip->res_port = devm_request_region(card->dev, port, 4, "WSS");
	if (!chip->res_port) {
		dev_err(chip->card->dev, "wss: can't grab port 0x%lx\n", port);
		return -EBUSY;
	}
	chip->port = port;
	if (!(hwshare & WSS_HWSHARE_IRQ))
		if (devm_request_irq(card->dev, irq, snd_wss_interrupt, 0,
				     "WSS", (void *) chip)) {
			dev_err(chip->card->dev, "wss: can't grab IRQ %d\n", irq);
			return -EBUSY;
		}
	chip->irq = irq;
	card->sync_irq = chip->irq;
	if (!(hwshare & WSS_HWSHARE_DMA1) &&
	    snd_devm_request_dma(card->dev, dma1, "WSS - 1")) {
		dev_err(chip->card->dev, "wss: can't grab DMA1 %d\n", dma1);
		return -EBUSY;
	}
	chip->dma1 = dma1;
	if (!(hwshare & WSS_HWSHARE_DMA2) && dma1 != dma2 && dma2 >= 0 &&
	    snd_devm_request_dma(card->dev, dma2, "WSS - 2")) {
		dev_err(chip->card->dev, "wss: can't grab DMA2 %d\n", dma2);
		return -EBUSY;
	}
	/* For my 560z, dma1=1 and dma2=3 so I removed the chip->single_dma
	 * and all the code related to it. */
	chip->dma2 = dma2;

	/* global setup */
	if (snd_wss_probe(chip) < 0)
		return -ENODEV;
	snd_wss_init(chip);

#if 0
	if (chip->hardware & WSS_HW_CS4232_MASK) {
		if (chip->res_cport == NULL)
			dev_err(chip->card->dev,
				"CS4232 control port features are not accessible\n");
	}
#endif

#ifdef CONFIG_PM
	/* Power Management */
	chip->suspend = snd_wss_suspend;
	chip->resume = snd_wss_resume;
#endif

	*rchip = chip;
	return 0;
}
EXPORT_SYMBOL(snd_wss_create);

static const struct snd_pcm_ops snd_wss_playback_ops = {
	.open =		snd_wss_playback_open,
	.close =	snd_wss_playback_close,
	.hw_params =	snd_wss_playback_hw_params,
	.prepare =	snd_wss_playback_prepare,
	.trigger =	snd_wss_trigger,
	.pointer =	snd_wss_playback_pointer,
};

static const struct snd_pcm_ops snd_wss_capture_ops = {
	.open =		snd_wss_capture_open,
	.close =	snd_wss_capture_close,
	.hw_params =	snd_wss_capture_hw_params,
	.prepare =	snd_wss_capture_prepare,
	.trigger =	snd_wss_trigger,
	.pointer =	snd_wss_capture_pointer,
};

int snd_wss_pcm(struct snd_wss *chip, int device)
{
	struct snd_pcm *pcm;
	int err;

	err = snd_pcm_new(chip->card, "WSS", device, 1, 1, &pcm);
	if (err < 0)
		return err;

	snd_pcm_set_ops(pcm, SNDRV_PCM_STREAM_PLAYBACK, &snd_wss_playback_ops);
	snd_pcm_set_ops(pcm, SNDRV_PCM_STREAM_CAPTURE, &snd_wss_capture_ops);

	/* global setup */
	pcm->private_data = chip;
	pcm->info_flags = 0;
	if (chip->hardware != WSS_HW_INTERWAVE)
		pcm->info_flags |= SNDRV_PCM_INFO_JOINT_DUPLEX;
	strscpy(pcm->name, snd_wss_chip_id(chip));

	snd_pcm_set_managed_buffer_all(pcm, SNDRV_DMA_TYPE_DEV, chip->card->dev,
				       64*1024, chip->dma1 > 3 || chip->dma2 > 3 ? 128*1024 : 64*1024);

	chip->pcm = pcm;
	return 0;
}
EXPORT_SYMBOL(snd_wss_pcm);

static void snd_wss_timer_free(struct snd_timer *timer)
{
	struct snd_wss *chip = timer->private_data;
	chip->timer = NULL;
}

int snd_wss_timer(struct snd_wss *chip, int device)
{
	struct snd_timer *timer;
	struct snd_timer_id tid;
	int err;

	/* Timer initialization */
	tid.dev_class = SNDRV_TIMER_CLASS_CARD;
	tid.dev_sclass = SNDRV_TIMER_SCLASS_NONE;
	tid.card = chip->card->number;
	tid.device = device;
	tid.subdevice = 0;
	err = snd_timer_new(chip->card, "CS4231", &tid, &timer);
	if (err < 0)
		return err;
	strscpy(timer->name, snd_wss_chip_id(chip));
	timer->private_data = chip;
	timer->private_free = snd_wss_timer_free;
	timer->hw = snd_wss_timer_table;
	chip->timer = timer;
	return 0;
}
EXPORT_SYMBOL(snd_wss_timer);

/*
 *  MIXER part
 */

static int snd_wss_info_mux(struct snd_kcontrol *kcontrol,
			    struct snd_ctl_elem_info *uinfo)
{
	static const char * const texts[4] = {
		"Line", "Aux", "Mic", "Mix"
	};
	static const char * const opl3sa_texts[4] = {
		"Line", "CD", "Mic", "Mix"
	};
	static const char * const gusmax_texts[4] = {
		"Line", "Synth", "Mic", "Mix"
	};
	const char * const *ptexts = texts;
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);

	if (snd_BUG_ON(!chip->card))
		return -EINVAL;
	if (!strcmp(chip->card->driver, "GUS MAX"))
		ptexts = gusmax_texts;
	switch (chip->hardware) {
	case WSS_HW_INTERWAVE:
		ptexts = gusmax_texts;
		break;
	case WSS_HW_OPTI93X:
	case WSS_HW_OPL3SA2:
		ptexts = opl3sa_texts;
		break;
	}
	return snd_ctl_enum_info(uinfo, 2, 4, ptexts);
}

static int snd_wss_get_mux(struct snd_kcontrol *kcontrol,
			   struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);

	guard(spinlock_irqsave)(&chip->reg_lock);
	ucontrol->value.enumerated.item[0] = (chip->image[CS4231_LEFT_INPUT] & CS4231_MIXS_ALL) >> 6;
	ucontrol->value.enumerated.item[1] = (chip->image[CS4231_RIGHT_INPUT] & CS4231_MIXS_ALL) >> 6;
	return 0;
}

static int snd_wss_put_mux(struct snd_kcontrol *kcontrol,
			   struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	unsigned short left, right;
	int change;

	if (ucontrol->value.enumerated.item[0] > 3 ||
	    ucontrol->value.enumerated.item[1] > 3)
		return -EINVAL;
	left = ucontrol->value.enumerated.item[0] << 6;
	right = ucontrol->value.enumerated.item[1] << 6;
	guard(spinlock_irqsave)(&chip->reg_lock);
	left = (chip->image[CS4231_LEFT_INPUT] & ~CS4231_MIXS_ALL) | left;
	right = (chip->image[CS4231_RIGHT_INPUT] & ~CS4231_MIXS_ALL) | right;
	change = left != chip->image[CS4231_LEFT_INPUT] ||
		 right != chip->image[CS4231_RIGHT_INPUT];
	snd_wss_out(chip, CS4231_LEFT_INPUT, left);
	snd_wss_out(chip, CS4231_RIGHT_INPUT, right);
	return change;
}

int snd_wss_info_single(struct snd_kcontrol *kcontrol,
			struct snd_ctl_elem_info *uinfo)
{
	int mask = (kcontrol->private_value >> 16) & 0xff;

	uinfo->type = mask == 1 ? SNDRV_CTL_ELEM_TYPE_BOOLEAN : SNDRV_CTL_ELEM_TYPE_INTEGER;
	uinfo->count = 1;
	uinfo->value.integer.min = 0;
	uinfo->value.integer.max = mask;
	return 0;
}
EXPORT_SYMBOL(snd_wss_info_single);

int snd_wss_get_single(struct snd_kcontrol *kcontrol,
		       struct snd_ctl_elem_value *ucontrol)
{
	struct snd_wss *chip = snd_kcontrol_chip(kcontrol);
	int reg = kcontrol->private_value & 0xff;
	int shift = (kcontrol->private_value >> 8) & 0xff;
	int mask = (kcontrol->private_value >> 16) & 0xff;
	int invert = (kcontrol->private_value >> 24) & 0xff;

	guard(spinlock_irqsave)(&chip->reg_lock);
	ucontrol->value.integer.value[0] = (chip->image[reg] >> shift) & mask;
	if (invert)
		ucontrol->value.integer.value[0] = mask - ucontrol->value.integer.value[0];
	return 0;
}
EXPORT_SYMBOL(snd_wss_get_single);

int snd_wss_put_single(struct snd_kcontrol *kcontrol,
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
	val = (chip->image[reg] & ~(mask << shift)) | val;
	change = val != chip->image[reg];
	snd_wss_out(chip, reg, val);
	return change;
}
EXPORT_SYMBOL(snd_wss_put_single);

int snd_wss_info_double(struct snd_kcontrol *kcontrol,
			struct snd_ctl_elem_info *uinfo)
{
	int mask = (kcontrol->private_value >> 24) & 0xff;

	uinfo->type = mask == 1 ? SNDRV_CTL_ELEM_TYPE_BOOLEAN : SNDRV_CTL_ELEM_TYPE_INTEGER;
	uinfo->count = 2;
	uinfo->value.integer.min = 0;
	uinfo->value.integer.max = mask;
	return 0;
}
EXPORT_SYMBOL(snd_wss_info_double);

int snd_wss_get_double(struct snd_kcontrol *kcontrol,
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
	ucontrol->value.integer.value[0] = (chip->image[left_reg] >> shift_left) & mask;
	ucontrol->value.integer.value[1] = (chip->image[right_reg] >> shift_right) & mask;
	if (invert) {
		ucontrol->value.integer.value[0] = mask - ucontrol->value.integer.value[0];
		ucontrol->value.integer.value[1] = mask - ucontrol->value.integer.value[1];
	}
	return 0;
}
EXPORT_SYMBOL(snd_wss_get_double);

int snd_wss_put_double(struct snd_kcontrol *kcontrol,
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
		val1 = (chip->image[left_reg] & ~(mask << shift_left)) | val1;
		val2 = (chip->image[right_reg] & ~(mask << shift_right)) | val2;
		change = val1 != chip->image[left_reg] ||
			 val2 != chip->image[right_reg];
		snd_wss_out(chip, left_reg, val1);
		snd_wss_out(chip, right_reg, val2);
	} else {
		mask = (mask << shift_left) | (mask << shift_right);
		val1 = (chip->image[left_reg] & ~mask) | val1 | val2;
		change = val1 != chip->image[left_reg];
		snd_wss_out(chip, left_reg, val1);
	}
	return change;
}
EXPORT_SYMBOL(snd_wss_put_double);

static const DECLARE_TLV_DB_SCALE(db_scale_6bit, -9450, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_5bit_12db_max, -3450, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_rec_gain, 0, 150, 0);
static const DECLARE_TLV_DB_SCALE(db_scale_4bit, -4500, 300, 0);

static const struct snd_kcontrol_new snd_wss_controls[] = {
WSS_DOUBLE("PCM Playback Switch", 0,
		CS4231_LEFT_OUTPUT, CS4231_RIGHT_OUTPUT, 7, 7, 1, 1),
WSS_DOUBLE_TLV("PCM Playback Volume", 0,
		CS4231_LEFT_OUTPUT, CS4231_RIGHT_OUTPUT, 0, 0, 63, 1,
		db_scale_6bit),
WSS_DOUBLE("Aux Playback Switch", 0,
		CS4231_AUX1_LEFT_INPUT, CS4231_AUX1_RIGHT_INPUT, 7, 7, 1, 1),
WSS_DOUBLE_TLV("Aux Playback Volume", 0,
		CS4231_AUX1_LEFT_INPUT, CS4231_AUX1_RIGHT_INPUT, 0, 0, 31, 1,
		db_scale_5bit_12db_max),
WSS_DOUBLE("Aux Playback Switch", 1,
		CS4231_AUX2_LEFT_INPUT, CS4231_AUX2_RIGHT_INPUT, 7, 7, 1, 1),
WSS_DOUBLE_TLV("Aux Playback Volume", 1,
		CS4231_AUX2_LEFT_INPUT, CS4231_AUX2_RIGHT_INPUT, 0, 0, 31, 1,
		db_scale_5bit_12db_max),
WSS_DOUBLE_TLV("Capture Volume", 0, CS4231_LEFT_INPUT, CS4231_RIGHT_INPUT,
		0, 0, 15, 0, db_scale_rec_gain),
{
	.iface = SNDRV_CTL_ELEM_IFACE_MIXER,
	.name = "Capture Source",
	.info = snd_wss_info_mux,
	.get = snd_wss_get_mux,
	.put = snd_wss_put_mux,
},
WSS_DOUBLE("Mic Boost (+20dB)", 0,
		CS4231_LEFT_INPUT, CS4231_RIGHT_INPUT, 5, 5, 1, 0),
WSS_SINGLE("Loopback Capture Switch", 0,
		CS4231_LOOPBACK, 0, 1, 0),
WSS_SINGLE_TLV("Loopback Capture Volume", 0, CS4231_LOOPBACK, 2, 63, 1,
		db_scale_6bit),
WSS_DOUBLE("Line Playback Switch", 0,
		CS4231_LEFT_LINE_IN, CS4231_RIGHT_LINE_IN, 7, 7, 1, 1),
WSS_DOUBLE_TLV("Line Playback Volume", 0,
		CS4231_LEFT_LINE_IN, CS4231_RIGHT_LINE_IN, 0, 0, 31, 1,
		db_scale_5bit_12db_max),
WSS_SINGLE("Beep Playback Switch", 0,
		CS4231_MONO_CTRL, 7, 1, 1),
WSS_SINGLE_TLV("Beep Playback Volume", 0,
		CS4231_MONO_CTRL, 0, 15, 1,
		db_scale_4bit),
WSS_SINGLE("Mono Output Playback Switch", 0,
		CS4231_MONO_CTRL, 6, 1, 1),
WSS_SINGLE("Beep Bypass Playback Switch", 0,
		CS4231_MONO_CTRL, 5, 1, 0),
};

int snd_wss_mixer(struct snd_wss *chip)
{
	struct snd_card *card;
	unsigned int idx;
	int err;
	int count = ARRAY_SIZE(snd_wss_controls);

	if (snd_BUG_ON(!chip || !chip->pcm))
		return -EINVAL;

	card = chip->card;

	strscpy(card->mixername, chip->pcm->name);

	/* Use only the first 11 entries on AD1848 */
	if (chip->hardware & WSS_HW_AD1848_MASK)
		count = 11;
	/* There is no loopback on OPTI93X */
	else if (chip->hardware == WSS_HW_OPTI93X)
		count = 9;

	for (idx = 0; idx < count; idx++) {
		err = snd_ctl_add(card,
				snd_ctl_new1(&snd_wss_controls[idx],
					     chip));
		if (err < 0)
			return err;
	}
	return 0;
}
EXPORT_SYMBOL(snd_wss_mixer);

const struct snd_pcm_ops *snd_wss_get_pcm_ops(int direction)
{
	return direction == SNDRV_PCM_STREAM_PLAYBACK ?
		&snd_wss_playback_ops : &snd_wss_capture_ops;
}
EXPORT_SYMBOL(snd_wss_get_pcm_ops);
