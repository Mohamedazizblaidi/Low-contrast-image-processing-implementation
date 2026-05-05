1) Total On-Chip Power = 0.989 W
This is the estimated total power used by your design on the chip.

It is composed of:

Dynamic power = 0.917 W
Static power = 0.072 W
So most of the power comes from switching activity in the logic.

2) Dynamic power = 93%
Dynamic power is power used when signals are changing during operation.

In your design:

lots of pixel processing
lots of combinational logic
many signal transitions
So dynamic power is the dominant part.

3) Static power = 7%
Static power is the power consumed even when the circuit is not switching.

This depends mainly on:

FPGA technology
device leakage
temperature
It is normal that static power is much smaller than dynamic power in your case.

Breakdown of dynamic power
Logic = 0.502 W → 55%
This is the biggest part.

It means your design uses a lot of:

LUTs
combinational logic
arithmetic operations
comparisons
So your image processing blocks are logic-heavy.

Signals = 0.366 W → 40%
This is power consumed by nets/wires when data moves around the FPGA.

This is high because:

pixel streams are wide
many signals toggle every clock
the image is processed continuously
Clocks = 0.017 W → 2%
Clock power is low here.

That means the clock network is not the main issue.

BRAM = 0.007 W → 1%
Very little Block RAM is used.

So your design is mostly logic-based, not memory-based.

DSP = 0.007 W → 1%
Very little DSP usage.

That means most arithmetic is not mapped to DSP blocks, but to LUT logic instead.

I/O = 0.019 W → 1%
This is power on input/output pins.

For your project, this is small and normal.

Temperature and thermal values
Junction Temperature = 29.9°C
This is the estimated chip temperature.

Thermal Margin = 55.1°C
This means the chip is still far from the thermal limit.

So from the power point of view, this design is safe.

Confidence level = Low
This is important.

Vivado says the confidence is low because the power estimate is based on:

synthesized netlist
estimated switching activity
no real simulation activity file
So this is only an approximation.
Actual power after implementation and real activity may change.

What this tells you about your design
Your design is:

logic heavy
signal heavy
not BRAM heavy
not DSP heavy
That matches an image-processing pipeline written in VHDL.

What you can say in a report
You can write:

The Vivado power analysis shows that the design consumes approximately 0.989 W on-chip power, with dynamic power dominating at 93%. The largest contributors are logic and signal switching activity, which is expected for a streaming image processing pipeline. BRAM and DSP usage are very small, indicating that the design is implemented mainly with LUT-based logic. The thermal margin remains safe, and the low confidence level indicates that the estimate may change after implementation and simulation-based activity profiling.

In simple words
This report means:

your design is working in simulation
it is not power-hungry
most power is spent in logic switching
the FPGA is not overheating
the estimate is only approximate