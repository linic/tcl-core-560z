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

#include <linux/init.h>
#include <linux/err.h>
#include <linux/isa.h>
#include <linux/pnp.h>
#include <linux/module.h>
#include <sound/core.h>
#include <sound/wss.h>
#include <sound/mpu401.h>
#include <sound/opl3.h>
#include <sound/initval.h>

MODULE_AUTHOR("Jaroslav Kysela <perex@perex.cz>");
MODULE_LICENSE("GPL");
/* MODULE_DESCRIPTION could probably be changed to CS4237B. */
MODULE_DESCRIPTION("Cirrus Logic CS4232-9");
MODULE_ALIAS("snd_cs4232");

/* IDENT and DEV_NAME could probably be changed to CS4237B. */
#define IDENT "CS4232+"
#define DEV_NAME "cs4232+"

static int index[SNDRV_CARDS] = SNDRV_DEFAULT_IDX;	/* Index 0-MAX */
static char *id[SNDRV_CARDS] = SNDRV_DEFAULT_STR;	/* ID for this card */
static bool enable[SNDRV_CARDS] = SNDRV_DEFAULT_ENABLE_ISAPNP; /* Enable this card */
static bool isapnp[SNDRV_CARDS] = {[0 ... (SNDRV_CARDS - 1)] = 1};
static long port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;	/* PnP setup */
static long mpu_port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;/* PnP setup */
static long fm_port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;	/* PnP setup */
static long sb_port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;	/* PnP setup */
static int irq[SNDRV_CARDS] = SNDRV_DEFAULT_IRQ;	/* 5,7,9,11,12,15 */
static int mpu_irq[SNDRV_CARDS] = SNDRV_DEFAULT_IRQ;	/* 9,11,12,15 */
static int dma1[SNDRV_CARDS] = SNDRV_DEFAULT_DMA;	/* 0,1,3,5,6,7 */
static int dma2[SNDRV_CARDS] = SNDRV_DEFAULT_DMA;	/* 0,1,3,5,6,7 */

module_param_array(index, int, NULL, 0444);
MODULE_PARM_DESC(index, "Index value for " IDENT " soundcard.");
module_param_array(id, charp, NULL, 0444);
MODULE_PARM_DESC(id, "ID string for " IDENT " soundcard.");
module_param_array(enable, bool, NULL, 0444);
MODULE_PARM_DESC(enable, "Enable " IDENT " soundcard.");
module_param_array(isapnp, bool, NULL, 0444);
MODULE_PARM_DESC(isapnp, "ISA PnP detection for specified soundcard.");
module_param_hw_array(port, long, ioport, NULL, 0444);
/* cport was removed since it's not available on the 560z. */
MODULE_PARM_DESC(port, "Port # for " IDENT " driver.");
module_param_hw_array(mpu_port, long, ioport, NULL, 0444);
MODULE_PARM_DESC(mpu_port, "MPU-401 port # for " IDENT " driver.");
module_param_hw_array(fm_port, long, ioport, NULL, 0444);
MODULE_PARM_DESC(fm_port, "FM port # for " IDENT " driver.");
module_param_hw_array(sb_port, long, ioport, NULL, 0444);
MODULE_PARM_DESC(sb_port, "SB port # for " IDENT " driver (optional).");
module_param_hw_array(irq, int, irq, NULL, 0444);
MODULE_PARM_DESC(irq, "IRQ # for " IDENT " driver.");
module_param_hw_array(mpu_irq, int, irq, NULL, 0444);
MODULE_PARM_DESC(mpu_irq, "MPU-401 IRQ # for " IDENT " driver.");
module_param_hw_array(dma1, int, dma, NULL, 0444);
MODULE_PARM_DESC(dma1, "DMA1 # for " IDENT " driver.");
module_param_hw_array(dma2, int, dma, NULL, 0444);
MODULE_PARM_DESC(dma2, "DMA2 # for " IDENT " driver.");

static int isa_registered;
static int pnpc_registered;
static int pnp_registered;

struct snd_card_cs4236 {
	struct snd_wss *chip;
	struct pnp_dev *wss;
	struct pnp_dev *ctrl;
	struct pnp_dev *mpu;
};

/*
 * PNP BIOS
 */
static const struct pnp_device_id snd_cs423x_pnpbiosids[] = {
	{ .id = "CSC0100" },
	{ .id = "CSC0000" },
	/* Guillemot Turtlebeach something appears to be cs4232 compatible
	 * (untested) */
	{ .id = "GIM0100" },
	{ .id = "" }
};
MODULE_DEVICE_TABLE(pnp, snd_cs423x_pnpbiosids);

/* On my 560z, I only have CSC0000 and CSC0001. I replaced all the values below. 
 * CSC0001 is looking like the game port on my 560z. I tried using it as the
 * control device because I thought it didn't make much sense to expose a game port
 * device since there's no physical game port on the 560z, but it didn't work as a control
 * port. Who knows... maybe the docking station which I don't have has a game port?
 * Anyway, I'm not sure if snd_cs423x_pnpids is used during the detection of the CS4237B
 * for my 560z and since I got sound working, I didn't investigate further. */
#define CS423X_ISAPNP_DRIVER	"cs4232_isapnp"
static const struct pnp_card_device_id snd_cs423x_pnpids[] = {
	/* Philips PCA70PS */
	{ .id = "CSC0d32", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* TerraTec Maestro 32/96 (CS4232) */
	{ .id = "CSC1a32", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* HP Omnibook 5500 onboard */
	{ .id = "CSC4232", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Unnamed CS4236 card (Made in Taiwan) */
	{ .id = "CSC4236", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Turtle Beach TBS-2000 (CS4232) */
	{ .id = "CSC7532", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Turtle Beach Tropez Plus (CS4232) */
	{ .id = "CSC7632", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* SIC CrystalWave 32 (CS4232) */
	{ .id = "CSCf032", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Netfinity 3000 on-board soundcard */
	{ .id = "CSCe825", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Intel Marlin Spike Motherboard - CS4235 */
	{ .id = "CSC0225", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Intel Marlin Spike Motherboard (#2) - CS4235 */
	{ .id = "CSC0225", .devs = { { "CSC0100" }, { "CSC0001" } } },
	/* Unknown Intel mainboard - CS4235 */
	{ .id = "CSC0225", .devs = { { "CSC0100" }, { "CSC0001" } } },
	/* Genius Sound Maker 3DJ - CS4237B */
	{ .id = "CSC0437", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Digital PC 5000 Onboard - CS4236B */
	{ .id = "CSC0735", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* some unknown CS4236B */
	{ .id = "CSC0b35", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Intel PR440FX Onboard sound */
	{ .id = "CSC0b36", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* CS4235 on mainboard without MPU */
	{ .id = "CSC1425", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Gateway E1000 Onboard CS4236B */
	{ .id = "CSC1335", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* HP 6330 Onboard sound */
	{ .id = "CSC1525", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Crystal Computer TidalWave128 */
	{ .id = "CSC1e37", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* ACER AW37 - CS4235 */
	{ .id = "CSC4236", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* build-in soundcard in EliteGroup P5TX-LA motherboard - CS4237B */
	{ .id = "CSC4237", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Crystal 3D - CS4237B */
	{ .id = "CSC4336", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Typhoon Soundsystem PnP - CS4236B */
	{ .id = "CSC4536", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Crystal CX4235-XQ3 EP - CS4235 */
	{ .id = "CSC4625", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Crystal Semiconductors CS4237B */
	{ .id = "CSC4637", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* NewClear 3D - CX4237B-XQ3 */
	{ .id = "CSC4837", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Dell Optiplex GX1 - CS4236B */
	{ .id = "CSC6835", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Dell P410 motherboard - CS4236B */
	{ .id = "CSC6835", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Dell Workstation 400 Onboard - CS4236B */
	{ .id = "CSC6836", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Turtle Beach Malibu - CS4237B */
	{ .id = "CSC7537", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* CS4235 - onboard */
	{ .id = "CSC8025", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* IBM Aptiva 2137 E24 Onboard - CS4237B */
	{ .id = "CSC8037", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* IBM IntelliStation M Pro motherboard */
	{ .id = "CSCc835", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Guillemot MaxiSound 16 PnP - CS4236B */
	{ .id = "CSC9836", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Gallant SC-70P */
	{ .id = "CSC9837", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Techmakers MF-4236PW */
	{ .id = "CSCa736", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* TerraTec AudioSystem EWS64XL - CS4236B */
	{ .id = "CSCa836", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* TerraTec AudioSystem EWS64XL - CS4236B */
	{ .id = "CSCa836", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* ACER AW37/Pro - CS4235 */
	{ .id = "CSCd925", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* ACER AW35/Pro - CS4237B */
	{ .id = "CSCd937", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* CS4235 without MPU401 */
	{ .id = "CSCe825", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* Unknown SiS530 - CS4235 */
	{ .id = "CSC4825", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* IBM IntelliStation M Pro 6898 11U - CS4236B */
	{ .id = "CSCe835", .devs = { { "CSC0000" }, { "CSC0010" } } },
	/* IBM PC 300PL Onboard - CS4236B */
	{ .id = "CSCe836", .devs = { { "CSC0000" }, { "CSC0010" } } },
	/* Some noname CS4236 based card */
	{ .id = "CSCe936", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* CS4236B */
	{ .id = "CSCf235", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* CS4236B */
	{ .id = "CSCf238", .devs = { { "CSC0000" }, { "CSC0001" } } },
	/* --- */
	{ .id = "" }	/* end */
};

MODULE_DEVICE_TABLE(pnp_card, snd_cs423x_pnpids);

/* WSS initialization */
static int snd_cs423x_pnp_init_wss(int dev, struct pnp_dev *pdev)
{
	if (pnp_activate_dev(pdev) < 0) {
		dev_dbg(&pdev->dev, IDENT " WSS PnP configure failed for WSS (out of resources?)\n");
		return -EBUSY;
	}
	port[dev] = pnp_port_start(pdev, 0);
	if (fm_port[dev] > 0)
		fm_port[dev] = pnp_port_start(pdev, 1);
	sb_port[dev] = pnp_port_start(pdev, 2);
	irq[dev] = pnp_irq(pdev, 0);
	dma1[dev] = pnp_dma(pdev, 0);
	dma2[dev] = pnp_dma(pdev, 1) == 4 ? -1 : (int)pnp_dma(pdev, 1);
	dev_dbg(&pdev->dev,
		"isapnp WSS: wss port=0x%lx, fm port=0x%lx, sb port=0x%lx\n",
		port[dev], fm_port[dev], sb_port[dev]);
	dev_dbg(&pdev->dev,
		"isapnp WSS: irq=%i, dma1=%i, dma2=%i\n",
		irq[dev], dma1[dev], dma2[dev]);
	return 0;
}

/* pnp init wss for the sound card
 * modified to not use the cdev since it doesn't exist for the 560z. */
static int snd_card_cs423x_pnp(int dev, struct snd_card_cs4236 *acard, struct pnp_dev *pdev)
{
	acard->wss = pdev;
	if (snd_cs423x_pnp_init_wss(dev, acard->wss) < 0)
		return -EBUSY;
	/* cdev est null pour mon 560z. Il n'y a pas de control. Le reste du code a ete ajuste. */
	return 0;
}

static int snd_card_cs423x_pnpc(int dev, struct snd_card_cs4236 *acard,
				struct pnp_card_link *card,
				const struct pnp_card_device_id *id)
{
	acard->wss = pnp_request_card_device(card, id->devs[0].id, NULL);
	if (acard->wss == NULL)
		return -EBUSY;
	dev_dbg(&acard->wss->dev, "snd_card_cs423x_pnpc - wss device found :)\n");
	acard->ctrl = pnp_request_card_device(card, id->devs[1].id, NULL);
	if (acard->ctrl == NULL)
		return -EBUSY;
	dev_dbg(&acard->ctrl->dev, "snd_card_cs423x_pnpc - ctrl device found :)\n");
	if (id->devs[2].id[0]) {
		acard->mpu = pnp_request_card_device(card, id->devs[2].id, NULL);
		if (acard->mpu == NULL)
			return -EBUSY;
	}
	dev_dbg(&acard->mpu->dev, "snd_card_cs423x_pnpc - mpu device found :)\n");

	/* WSS initialization */
	if (snd_cs423x_pnp_init_wss(dev, acard->wss) < 0)
		return -EBUSY;

	return 0;
}

#define is_isapnp_selected(dev)		isapnp[dev]

static int snd_cs423x_card_new(struct device *pdev, int dev,
			       struct snd_card **cardp)
{
	struct snd_card *card;
	int err;

	err = snd_devm_card_new(pdev, index[dev], id[dev], THIS_MODULE,
				sizeof(struct snd_card_cs4236), &card);
	if (err < 0)
		return err;
	*cardp = card;
	return 0;
}

static int snd_cs423x_probe(struct snd_card *card, int dev)
{
	struct snd_card_cs4236 *acard;
	struct snd_wss *chip;
	struct snd_opl3 *opl3;
	int err;

	acard = card->private_data;
	if (sb_port[dev] > 0 && sb_port[dev] != SNDRV_AUTO_PORT) {
		if (!devm_request_region(card->dev, sb_port[dev], 16,
					 IDENT " SB")) {
			dev_dbg(card->dev, IDENT ": unable to register SB port at 0x%lx\n",
				sb_port[dev]);
			return -EBUSY;
		}
	}

	err = snd_cs4236_create(card, port[dev], irq[dev], dma1[dev], dma2[dev], WSS_HW_DETECT3, 0, &chip);
	if (err < 0)
		return err;

	acard->chip = chip;
	if (chip->hardware & WSS_HW_CS4236B_MASK) {

		err = snd_cs4236_pcm(chip, 0);
		if (err < 0)
			return err;

		err = snd_cs4236_mixer(chip);
		if (err < 0)
			return err;
	} else {
		err = snd_wss_pcm(chip, 0);
		if (err < 0)
			return err;

		err = snd_wss_mixer(chip);
		if (err < 0)
			return err;
	}
	strscpy(card->driver, chip->pcm->name, sizeof(card->driver));
	strscpy(card->shortname, chip->pcm->name, sizeof(card->shortname));
	if (dma2[dev] < 0)
		scnprintf(card->longname, sizeof(card->longname),
			  "%s at 0x%lx, irq %i, dma %i",
			  chip->pcm->name, chip->port, irq[dev], dma1[dev]);
	else
		scnprintf(card->longname, sizeof(card->longname),
			  "%s at 0x%lx, irq %i, dma %i&%d",
			  chip->pcm->name, chip->port, irq[dev], dma1[dev],
			  dma2[dev]);

	err = snd_wss_timer(chip, 0);
	if (err < 0)
		return err;

	if (fm_port[dev] > 0 && fm_port[dev] != SNDRV_AUTO_PORT) {
		if (snd_opl3_create(card,
				    fm_port[dev], fm_port[dev] + 2,
				    OPL3_HW_OPL3_CS, 0, &opl3) < 0) {
			dev_warn(card->dev, IDENT ": OPL3 not detected\n");
		} else {
			err = snd_opl3_hwdep_new(opl3, 0, 1, NULL);
			if (err < 0)
				return err;
		}
	}

	if (mpu_port[dev] > 0 && mpu_port[dev] != SNDRV_AUTO_PORT) {
		if (mpu_irq[dev] == SNDRV_AUTO_IRQ)
			mpu_irq[dev] = -1;
		if (snd_mpu401_uart_new(card, 0, MPU401_HW_CS4232,
					mpu_port[dev], 0,
					mpu_irq[dev], NULL) < 0)
			dev_warn(card->dev, IDENT ": MPU401 not detected\n");
	}

	return snd_card_register(card);
}

static int snd_cs423x_isa_match(struct device *pdev, unsigned int dev)
{
	if (!enable[dev] || is_isapnp_selected(dev))
		return 0;

	if (port[dev] == SNDRV_AUTO_PORT) {
		dev_dbg(pdev, "please specify port\n");
		return 0;
	}
	if (irq[dev] == SNDRV_AUTO_IRQ) {
		dev_dbg(pdev, "please specify irq\n");
		return 0;
	}
	if (dma1[dev] == SNDRV_AUTO_DMA) {
		dev_dbg(pdev, "please specify dma1\n");
		return 0;
	}
	return 1;
}

static int snd_cs423x_isa_probe(struct device *pdev,
				unsigned int dev)
{
	struct snd_card *card;
	int err;

	err = snd_cs423x_card_new(pdev, dev, &card);
	if (err < 0)
		return err;
	err = snd_cs423x_probe(card, dev);
	if (err < 0)
		return err;
	dev_set_drvdata(pdev, card);
	return 0;
}

static int snd_cs423x_suspend(struct snd_card *card)
{
	struct snd_card_cs4236 *acard = card->private_data;
	snd_power_change_state(card, SNDRV_CTL_POWER_D3hot);
	acard->chip->suspend(acard->chip);
	return 0;
}

static int snd_cs423x_resume(struct snd_card *card)
{
	struct snd_card_cs4236 *acard = card->private_data;
	acard->chip->resume(acard->chip);
	snd_power_change_state(card, SNDRV_CTL_POWER_D0);
	return 0;
}

static int snd_cs423x_isa_suspend(struct device *dev, unsigned int n,
				  pm_message_t state)
{
	return snd_cs423x_suspend(dev_get_drvdata(dev));
}

static int snd_cs423x_isa_resume(struct device *dev, unsigned int n)
{
	return snd_cs423x_resume(dev_get_drvdata(dev));
}

static struct isa_driver cs423x_isa_driver = {
	.match		= snd_cs423x_isa_match,
	.probe		= snd_cs423x_isa_probe,
	.suspend	= snd_cs423x_isa_suspend,
	.resume		= snd_cs423x_isa_resume,
	.driver		= {
		.name	= DEV_NAME
	},
};


/* Ceci est appele par defaut lorsque les modules sont presents. 
 * sur mon 560z. Lorsqu'arrive le temps d'appeler snd_card_cs423x_pnp
 * cdev est NULL.*/
static int snd_cs423x_pnpbios_detect(struct pnp_dev *pdev, const struct pnp_device_id *id)
{
	static int dev;
	int err;
	struct snd_card *card;
	struct pnp_dev *iter;

	if (pnp_device_is_isapnp(pdev))
		return -ENOENT;	/* we have another procedure - card */
	for (; dev < SNDRV_CARDS; dev++) {
		if (enable[dev] && isapnp[dev])
			break;
	}
	if (dev >= SNDRV_CARDS)
		return -ENODEV;

	/* La datasheet de la CS4237B dit que la DEVICE 2, soit le control:
	* LOGICAL DEVICE 0 (Windows Sound System & SBPro) CSC0000
	* LOGICAL DEVICE 1 (Game Port) CSC0001
	* LOGICAL DEVICE 2 (Control) CSC0010
	* LOGICAL DEVICE 3 (MPU-401) CSC0003
	* CSC0010, CSC0002 et CSC0003 n'existent pas sur mon 560Z
	* la liste dans l'ordre de ce qui existe:
	* iter->id->id=PNP0c01, iter->name=MBRM
	* iter->id->id=PNP0700, iter->name=FDC0
	* iter->id->id=PNP0501, iter->name=UAR1
	* iter->id->id=PNP0400, iter->name=LPT
	* iter->id->id=IBM0071, iter->name=FIR
	* iter->id->id=CSC0000, iter->name=CS00
	* iter->id->id=CSC0001, iter->name=CS01
	* iter->id->id=PNP0c02, iter->name=MBRD
	* iter->id->id=PNP0303, iter->name=KBD0
	* iter->id->id=IBM3781, iter->name=MOU0
	* iter->id->id=PNP0b00, iter->name=RTC0 */
	err = snd_cs423x_card_new(&pdev->dev, dev, &card);
	if (err < 0)
		return err;
	err = snd_card_cs423x_pnp(dev, card->private_data, pdev);
	if (err < 0) {
		dev_dbg(card->dev, "PnP BIOS detection failed for " IDENT "\n");
		return err;
	}
	/* pdev->id[0] est CSC0000 sur mon 560z, soit le Windows Sound System & SBPro. */
	dev_dbg(card->dev, IDENT " : pdev is EISA ID=%s, name=%s\n", pdev->id->id, pdev->name);
	/* lister toutes les devices ISA */
	list_for_each_entry(iter, &(pdev->protocol->devices), protocol_list) {
		dev_dbg(card->dev, IDENT " : EISA ID=%s, name=%s\n", iter->id->id, iter->name);
	}
	err = snd_cs423x_probe(card, dev);
	if (err < 0)
		return err;
	pnp_set_drvdata(pdev, card);
	dev++;
	return 0;
}

static int snd_cs423x_pnp_suspend(struct pnp_dev *pdev, pm_message_t state)
{
	return snd_cs423x_suspend(pnp_get_drvdata(pdev));
}

static int snd_cs423x_pnp_resume(struct pnp_dev *pdev)
{
	return snd_cs423x_resume(pnp_get_drvdata(pdev));
}

static struct pnp_driver cs423x_pnp_driver = {
	.name = "cs423x-pnpbios",
	.id_table = snd_cs423x_pnpbiosids,
	.probe = snd_cs423x_pnpbios_detect,
	.suspend	= snd_cs423x_pnp_suspend,
	.resume		= snd_cs423x_pnp_resume,
};

static int snd_cs423x_pnpc_detect(struct pnp_card_link *pcard,
				  const struct pnp_card_device_id *pid)
{
	static int dev;
	struct snd_card *card;
	int res;

	for ( ; dev < SNDRV_CARDS; dev++) {
		if (enable[dev] && isapnp[dev])
			break;
	}
	if (dev >= SNDRV_CARDS)
		return -ENODEV;

	res = snd_cs423x_card_new(&pcard->card->dev, dev, &card);
	if (res < 0)
		return res;
	res = snd_card_cs423x_pnpc(dev, card->private_data, pcard, pid);
	if (res < 0) {
		dev_dbg(card->dev, "isapnp detection failed and probing for " IDENT
		       " is not supported\n");
		return res;
	}
	res = snd_cs423x_probe(card, dev);
	if (res < 0)
		return res;
	pnp_set_card_drvdata(pcard, card);
	dev++;
	return 0;
}

static int snd_cs423x_pnpc_suspend(struct pnp_card_link *pcard, pm_message_t state)
{
	return snd_cs423x_suspend(pnp_get_card_drvdata(pcard));
}

static int snd_cs423x_pnpc_resume(struct pnp_card_link *pcard)
{
	return snd_cs423x_resume(pnp_get_card_drvdata(pcard));
}

static struct pnp_card_driver cs423x_pnpc_driver = {
	.flags = PNP_DRIVER_RES_DISABLE,
	.name = CS423X_ISAPNP_DRIVER,
	.id_table = snd_cs423x_pnpids,
	.probe = snd_cs423x_pnpc_detect,
	.suspend	= snd_cs423x_pnpc_suspend,
	.resume		= snd_cs423x_pnpc_resume,
};

/* 560z utilise cs423x_pnp_driver 
 * Je ne sais pas dans quelles conditions le isa_driver et
 * le pnpc_driver sont utilisés... */
static int __init alsa_card_cs423x_init(void)
{
	int err;

	err = isa_register_driver(&cs423x_isa_driver, SNDRV_CARDS);
	if (!err)
		isa_registered = 1;
	err = pnp_register_driver(&cs423x_pnp_driver);
	if (!err)
		pnp_registered = 1;
	err = pnp_register_card_driver(&cs423x_pnpc_driver);
	if (!err)
		pnpc_registered = 1;
	if (pnp_registered)
		err = 0;
	if (isa_registered)
		err = 0;
	return err;
}

static void __exit alsa_card_cs423x_exit(void)
{
	if (pnpc_registered)
		pnp_unregister_card_driver(&cs423x_pnpc_driver);
	if (pnp_registered)
		pnp_unregister_driver(&cs423x_pnp_driver);
	if (isa_registered)
		isa_unregister_driver(&cs423x_isa_driver);
}

module_init(alsa_card_cs423x_init)
module_exit(alsa_card_cs423x_exit)
