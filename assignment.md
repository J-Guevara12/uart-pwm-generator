# PWM generator controlled via UART

## Project Overview
The assignment focuses on designing a digital control system that modulates a PWM waveform whose frequency and duty cycle can be updated at run time via UART commands. Students must specify and implement the hardware logic that parses incoming messages, reconfigures the PWM core, and maintains observability of the current operating point. Emphasis is placed on clean module partitioning, robust handling of invalid inputs, and verification evidence that the UART to PWM control path behaves correctly across the specified operating envelope.

## PWM FSM Functional requirements
* Input clock frequency: 50 MHz.
* PWM clock highest frequency is 50 kHz.
* PWM clock frequency is set as
$$f_{PWM} = \dfrac{50~\text{kHz}}{(2^{POW2})\cdot(5^{POW5})}$$
* Valid values for $POW2$ and $POW5$ are 0, 1, 2 and 3.
* The lowest PWM frequency is 
$$f_{LOW} = \dfrac{50~\text{kHz}}{(2^3)\cdot(5^3)} = 50~\text{Hz}$$
* PWM duty cycle can be increased in steps of 1%, from 0% up to 99%. 
* Input duty cycle values upwards 99 are considered invalid and produce no changes in the actual duty cycle value.
* Pulses of the PWM signal should be centered within the cycle.

## UART Functional requirements
* Input clock frequency: 50 MHz.
* UART configuration: 115200 bauds; one start bit; one stop bit; no parity bits.
* At least one rest cycle between bytes sent (equivalent to one bit spacing).
* 32 bytes depth RX buffer.
    * Buffer stalls when full (no more characters can be stored). 
    * The buffer pointer resets everytime an end of string character is received.
    * An end of string flag is set everytime an end of string is received. The flag is active until a new start bit is detected.

## HMI Functional requirements
* The input string "HELP" should trigger a transmission of the help screen.
* The input string "STATUS" should trigger a transmission of the current frequency and duty cycle.
* The input string "DC##" should trigger a change in the PWM duty cycle, and the transmission of either "OK" if the operation succeeded, or "FAIL" if an invalid duty cycle is provided.
* The input string "POW2#" should trigger a change in the base 2 frequency downscaler if the parameter is either 0, 1, 2 or 3, and trigger a transmission of the "OK" string; or a transmission of "FAIL" string if the parameter is invalid.
* The input string "POW5#" should trigger a change in the base 5 frequency downscaler if the parameter is either 0, 1, 2 or 3, and trigger a transmission of the "OK" string; or a transmission of "FAIL" string if the parameter is invalid.
* Any unknown command received as input string should trigger the transmission of the message "FAIL".

## Complementary Design Guidance
* **System decomposition**: Provide a block-level diagram that highlights the PWM generator, UART RX/TX pipeline, command parser, configuration registers, and clock-domain considerations. Explain signal interactions and clock enables derived from POW2/POW5 dividers.
* **RTL deliverables**: Submit synthesizable RTL for PWM control, frequency scaling, UART interface, and the command interpreter. Each module should include a brief header comment describing its intent, I/O, and assumptions.
* **Parameter handling**: Define how illegal parameters are filtered, latched, and reported. Document reset values, update latency, and any metastability mitigation techniques for cross-module handshakes.
* **Documentation expectations**: Deliver a short design note covering architectural decisions, register map, command protocol, and edge cases (e.g., simultaneous command requests, buffer overflow recovery).

## Verification and Validation Expectations
* **Simulation strategy**: Describe a layered testbench that separates stimulus generation, protocol encoding, and checking. Justify the mix of directed sequences (e.g., boundary duty-cycle updates, POW2/POW5 sweeps) and constrained-random bursts exercising command interleaving and buffer pressure. Model the UART channel at the bit level—including start/stop framing and inter-byte spacing—so timing violations, framing errors, and RX buffer stalls can be observed. Highlight self-checking mechanisms such as scoreboards comparing expected PWM envelopes against sampled outputs, assertions monitoring handshake correctness, and protocol monitors flagging malformed packets. Include waveform captures or log excerpts that document bug discovery and resolution.
* **Coverage goals**: Define functional coverage points that track all legal POW2/POW5 combinations, duty-cycle transitions (0%, mid-range, 99%), invalid command injection, buffer overflow and recovery, and end-of-string flag behavior. Explain how cross-coverage between command types and PWM outcomes ensures the configuration space is exercised. Report statement/branch coverage when available, calling out modules that require additional tests to close gaps and discussing any exclusions. Establish clear exit criteria (e.g., ≥95% functional bins hit, no uncovered high-priority scenarios) tied back to the functional requirements.
* **Regression artifacts**: Provide scripts or make targets to rerun the full regression. Capture pass/fail criteria and summarize test results in the final report.

## Assessment Rubric
* **Design quality (0–10 pts)**
  * 0–3: Incomplete RTL, unclear module boundaries, missing reset/clock handling, or non-functional implementation.
  * 4–6: Functional baseline design with basic documentation; limited discussion of trade-offs or corner cases.
  * 7–8: Well-structured modular design with clear interface definitions, thoughtful parameter handling, and rationale for key architectural choices.
  * 9–10: Production-ready presentation with comprehensive documentation, thoroughly justified architecture, and demonstrable robustness against edge conditions.
* **Testbench quality (0–10 pts)**
  * 0–3: Minimal stimulus, missing UART modeling, little to no checking or coverage.
  * 4–6: Directed tests covering nominal flows, partial checking, limited automation, or sporadic coverage metrics.
  * 7–8: Self-checking environment with protocol-accurate UART models, regression infrastructure, and coverage analysis driving additional tests.
  * 9–10: Comprehensive verification plan realized with layered environment, thorough corner-case exploration, high coverage closure, and clear traceability to requirements.
* **Use of AI (0–5 pts)**
  * 0–1: No meaningful engagement with AI tools or uncredited outputs.
  * 2–3: AI leveraged for brainstorming or code assistance with basic reflection on its impact.
  * 4: Clear documentation of AI interactions, critical evaluation of suggestions, and evidence of human oversight.
  * 5: Exemplary, transparent integration of AI throughout the workflow that improves design or verification outcomes while maintaining academic integrity.
