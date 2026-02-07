I created the patch on 6.18.8 by re-reading through my original
patch on a previous 6.x kernel.

I decided to put back the #ifdef CONFIG_PM since power management
should not affect whether the sound is working or not.

Previously, I had removed these instructions and the power
management code would always be compiled in.

From memory, this applies to my 5.10.x patch and my 4.4.x patch.
