# For the Flycast games (Crazy Taxi 2, The House of the Dead 2...). On the Pi:
# ~/.config/retroarch/filters/cab/CabClear.dsp, beside a copy of RetroArch's iir.so.
# These games put about half their sound below 150 Hz, which the table's small speakers
# cannot play; boosted with everything else it only made them rumble and blur the rest.
# A high-pass filter: what is below the frequency is turned down, more the lower it is.
filters = 1
filter0 = iir
iir_type = HPF
iir_frequency = 120.0
iir_quality = 0.707
iir_gain = 0.0
