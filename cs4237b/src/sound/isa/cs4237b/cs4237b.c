// SPDX-License-Identifier: GPL-2.0-only
/*
 *  PnP / ISA bus glue for the Cirrus Logic CS4237B (no-control-port)
 *  ALSA driver.
 *
 *  Derived from sound/isa/cs423x/cs4236.c (Linux 6.18.8) by Jaroslav
 *  Kysela <perex@perex.cz>. The control-port logic — sibling-ID
 *  search, cport module parameter, ISAPNP card-driver path that
 *  requires CSC0010 — has been removed. This module binds only to
 *  the WSS-side PnP logical device (CSC0000), passes cport = -1 down
 *  to snd_wss_create(), and lets the chip come up using only WSS-side
 *  registers.
 *
 *  Best-known target: the IBM/Lenovo ThinkPad 560Z, on which the
 *  separate CSC0010 control device is not exposed by the BIOS.
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

#include "cs4237b.h"

MODULE_AUTHOR("Nic Brochu");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Cirrus Logic CS4237B (no control port) ALSA driver");
MODULE_ALIAS("snd-cs4237b");

#define IDENT "CS4237B"
#define DEV_NAME "cs4237b"

static int index[SNDRV_CARDS] = SNDRV_DEFAULT_IDX;
static char *id[SNDRV_CARDS] = SNDRV_DEFAULT_STR;
static bool enable[SNDRV_CARDS] = SNDRV_DEFAULT_ENABLE_ISAPNP;
#ifdef CONFIG_PNP
static bool isapnp[SNDRV_CARDS] = {[0 ... (SNDRV_CARDS - 1)] = 1};
#endif
static long port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;
static long mpu_port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;
static long fm_port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;
static long sb_port[SNDRV_CARDS] = SNDRV_DEFAULT_PORT;
static int irq[SNDRV_CARDS] = SNDRV_DEFAULT_IRQ;
static int mpu_irq[SNDRV_CARDS] = SNDRV_DEFAULT_IRQ;
static int dma1[SNDRV_CARDS] = SNDRV_DEFAULT_DMA;
static int dma2[SNDRV_CARDS] = SNDRV_DEFAULT_DMA;

module_param_array(index, int, NULL, 0444);
MODULE_PARM_DESC(index, "Index value for " IDENT " soundcard.");
module_param_array(id, charp, NULL, 0444);
MODULE_PARM_DESC(id, "ID string for " IDENT " soundcard.");
module_param_array(enable, bool, NULL, 0444);
MODULE_PARM_DESC(enable, "Enable " IDENT " soundcard.");
#ifdef CONFIG_PNP
module_param_array(isapnp, bool, NULL, 0444);
MODULE_PARM_DESC(isapnp, "ISA PnP detection for specified soundcard.");
#endif
module_param_hw_array(port, long, ioport, NULL, 0444);
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

#ifdef CONFIG_PNP
static int isa_registered;
static int pnp_registered;
#endif

struct snd_card_cs4237b {
	struct snd_wss *chip;
#ifdef CONFIG_PNP
	struct pnp_dev *wss;
#endif
};

#ifdef CONFIG_PNP

/*
 *  PnP-BIOS match table. Only the WSS-side logical device is
 *  claimed; the separate CSC0010 control device is intentionally
 *  not listed — that is the whole point of this driver.
 */
static const struct pnp_device_id snd_cs4237b_pnpbiosids[] = {
	{ .id = "CSC0000" },
	{ .id = "" }
};
MODULE_DEVICE_TABLE(pnp, snd_cs4237b_pnpbiosids);

static int snd_cs4237b_pnp_init_wss(int dev, struct pnp_dev *pdev)
{
	if (pnp_activate_dev(pdev) < 0) {
		dev_err(&pdev->dev,
			IDENT " WSS PnP configure failed (out of resources?)\n");
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
		"isapnp WSS: wss=0x%lx fm=0x%lx sb=0x%lx irq=%i dma1=%i dma2=%i\n",
		port[dev], fm_port[dev], sb_port[dev],
		irq[dev], dma1[dev], dma2[dev]);
	return 0;
}

#endif /* CONFIG_PNP */

#ifdef CONFIG_PNP
#define is_isapnp_selected(dev)		isapnp[dev]
#else
#define is_isapnp_selected(dev)		0
#endif

static int snd_cs4237b_card_new(struct device *pdev, int dev,
				struct snd_card **cardp)
{
	struct snd_card *card;
	int err;

	err = snd_devm_card_new(pdev, index[dev], id[dev], THIS_MODULE,
				sizeof(struct snd_card_cs4237b), &card);
	if (err < 0)
		return err;
	*cardp = card;
	return 0;
}

static int snd_cs4237b_probe(struct snd_card *card, int dev)
{
	struct snd_card_cs4237b *acard;
	struct snd_wss *chip;
	struct snd_opl3 *opl3;
	int err;

	acard = card->private_data;
	if (sb_port[dev] > 0 && sb_port[dev] != SNDRV_AUTO_PORT) {
		if (!devm_request_region(card->dev, sb_port[dev], 16,
					 IDENT " SB")) {
			dev_err(card->dev,
				IDENT ": unable to register SB port at 0x%lx\n",
				sb_port[dev]);
			return -EBUSY;
		}
	}

	err = snd_cs4237b_create(card, port[dev],
				 irq[dev], dma1[dev], dma2[dev], &chip);
	if (err < 0)
		return err;

	acard->chip = chip;

	err = snd_cs4237b_pcm(chip, 0);
	if (err < 0)
		return err;

	err = snd_cs4237b_mixer(chip);
	if (err < 0)
		return err;

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

static int snd_cs4237b_isa_match(struct device *pdev, unsigned int dev)
{
	if (!enable[dev] || is_isapnp_selected(dev))
		return 0;

	if (port[dev] == SNDRV_AUTO_PORT) {
		dev_err(pdev, "please specify port\n");
		return 0;
	}
	if (irq[dev] == SNDRV_AUTO_IRQ) {
		dev_err(pdev, "please specify irq\n");
		return 0;
	}
	if (dma1[dev] == SNDRV_AUTO_DMA) {
		dev_err(pdev, "please specify dma1\n");
		return 0;
	}
	return 1;
}

static int snd_cs4237b_isa_probe(struct device *pdev, unsigned int dev)
{
	struct snd_card *card;
	int err;

	err = snd_cs4237b_card_new(pdev, dev, &card);
	if (err < 0)
		return err;
	err = snd_cs4237b_probe(card, dev);
	if (err < 0)
		return err;
	dev_set_drvdata(pdev, card);
	return 0;
}

#ifdef CONFIG_PM
static int snd_cs4237b_suspend(struct snd_card *card)
{
	struct snd_card_cs4237b *acard = card->private_data;

	snd_power_change_state(card, SNDRV_CTL_POWER_D3hot);
	acard->chip->suspend(acard->chip);
	return 0;
}

static int snd_cs4237b_resume(struct snd_card *card)
{
	struct snd_card_cs4237b *acard = card->private_data;

	acard->chip->resume(acard->chip);
	snd_power_change_state(card, SNDRV_CTL_POWER_D0);
	return 0;
}

static int snd_cs4237b_isa_suspend(struct device *dev, unsigned int n,
				   pm_message_t state)
{
	return snd_cs4237b_suspend(dev_get_drvdata(dev));
}

static int snd_cs4237b_isa_resume(struct device *dev, unsigned int n)
{
	return snd_cs4237b_resume(dev_get_drvdata(dev));
}
#endif

static struct isa_driver cs4237b_isa_driver = {
	.match		= snd_cs4237b_isa_match,
	.probe		= snd_cs4237b_isa_probe,
#ifdef CONFIG_PM
	.suspend	= snd_cs4237b_isa_suspend,
	.resume		= snd_cs4237b_isa_resume,
#endif
	.driver		= {
		.name	= DEV_NAME
	},
};

#ifdef CONFIG_PNP
static int snd_cs4237b_pnpbios_detect(struct pnp_dev *pdev,
				      const struct pnp_device_id *pid)
{
	static int dev;
	int err;
	struct snd_card *card;
	struct snd_card_cs4237b *acard;

	if (pnp_device_is_isapnp(pdev))
		return -ENOENT;
	for (; dev < SNDRV_CARDS; dev++) {
		if (enable[dev] && isapnp[dev])
			break;
	}
	if (dev >= SNDRV_CARDS)
		return -ENODEV;

	err = snd_cs4237b_card_new(&pdev->dev, dev, &card);
	if (err < 0)
		return err;
	acard = card->private_data;
	acard->wss = pdev;
	if (snd_cs4237b_pnp_init_wss(dev, acard->wss) < 0)
		return -EBUSY;
	err = snd_cs4237b_probe(card, dev);
	if (err < 0)
		return err;
	pnp_set_drvdata(pdev, card);
	dev++;
	return 0;
}

#ifdef CONFIG_PM
static int snd_cs4237b_pnp_suspend(struct pnp_dev *pdev, pm_message_t state)
{
	return snd_cs4237b_suspend(pnp_get_drvdata(pdev));
}

static int snd_cs4237b_pnp_resume(struct pnp_dev *pdev)
{
	return snd_cs4237b_resume(pnp_get_drvdata(pdev));
}
#endif

static struct pnp_driver cs4237b_pnp_driver = {
	.name		= "cs4237b-pnpbios",
	.id_table	= snd_cs4237b_pnpbiosids,
	.probe		= snd_cs4237b_pnpbios_detect,
#ifdef CONFIG_PM
	.suspend	= snd_cs4237b_pnp_suspend,
	.resume		= snd_cs4237b_pnp_resume,
#endif
};
#endif /* CONFIG_PNP */

static int __init alsa_card_cs4237b_init(void)
{
	int err;

	err = isa_register_driver(&cs4237b_isa_driver, SNDRV_CARDS);
#ifdef CONFIG_PNP
	if (!err)
		isa_registered = 1;
	err = pnp_register_driver(&cs4237b_pnp_driver);
	if (!err)
		pnp_registered = 1;
	if (pnp_registered)
		err = 0;
	if (isa_registered)
		err = 0;
#endif
	return err;
}

static void __exit alsa_card_cs4237b_exit(void)
{
#ifdef CONFIG_PNP
	if (pnp_registered)
		pnp_unregister_driver(&cs4237b_pnp_driver);
	if (isa_registered)
#endif
		isa_unregister_driver(&cs4237b_isa_driver);
}

module_init(alsa_card_cs4237b_init)
module_exit(alsa_card_cs4237b_exit)
