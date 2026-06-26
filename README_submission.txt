README — Final Project Submission
==================================
Student: Anker Rasmussen
Project: Lattice: Privacy-Preserving Sealed-Bid Auctions over Veilid with MPC
Consultant: Martin Brain (Academic Client)

Submitted Files
----------------
1. Dissertation.pdf
   The project report including all textual appendices:
   - Chapter 1: Introduction
   - Chapter 2: Output Summary
   - Chapter 3: Context (Literature Review)
   - Chapter 4: Method
   - Chapter 5: Results
   - Chapter 6: Conclusions and Discussion
   - Appendix A: Project Definition Document (PDD)
   - Appendix B: Reuse Summary
   - Appendix C: Supervisory Meeting Minutes
   - Appendix D: Generative AI Usage Declaration
   - Appendix E: Veilid Developer Correspondence

2. submission_source.txt
   All Rust source code written by the author (src/ and tests/),
   concatenated into a single text file.  This includes:
   - src/          Application source (~15,000 lines)
   - tests/        Integration and E2E test code
   - Repos/MP-SPDZ/Programs/Source/auction_n.mpc
                   The MPC auction program (MP-SPDZ)
   - Repos/veilid/playground/  Veilid playground orchestrator (Rust)
   - Repos/veilid/ipspoof/     Rust LD_PRELOAD IP spoofing library
   Does NOT include: third-party library code, generated code, or
   build artifacts.

3. README_submission.txt
   This file.

Repository
-----------
The full project repository (including git history, submodules,
build scripts, benchmark data, and LaTeX sources) is available at:

  https://github.com/anker-rasmussen/Dissertation

The main application crate is in:
  Repos/dissertationapp/market/

To build and run, see the Makefile targets documented in the report
(Chapter 4, Section 4.1) and the repository README.

Product Package
----------------
The product package (source code, build instructions, devnet setup)
is submitted separately as per the earlier deadline.  The repository
above contains the complete product.

Demo Video
-----------
The 15-minute project demonstration video is submitted separately
to the video submission area.
