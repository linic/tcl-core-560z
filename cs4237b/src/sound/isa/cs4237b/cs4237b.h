/* SPDX-License-Identifier: GPL-2.0-only */
/*
 *  Private header for the CS4237B (no-control-port) ALSA driver.
 *
 *  This module talks to the chip exclusively through the WSS-side
 *  registers, which is the only path available on boards that do not
 *  expose the CSC0010 PnP "Control" logical device (e.g. ThinkPad
 *  560Z). It deliberately does NOT declare or shadow struct snd_wss;
 *  the unmodified <sound/wss.h> definition is used and the cport /
 *  res_cport / cimage[] fields it carries simply remain untouched.
 */

#ifndef __SOUND_ISA_CS4237B_H
#define __SOUND_ISA_CS4237B_H

#include <sound/core.h>
#include <sound/wss.h>

int snd_cs4237b_create(struct snd_card *card,
		       unsigned long port,
		       int irq, int dma1, int dma2,
		       struct snd_wss **rchip);

int snd_cs4237b_pcm(struct snd_wss *chip, int device);
int snd_cs4237b_mixer(struct snd_wss *chip);

#endif /* __SOUND_ISA_CS4237B_H */
