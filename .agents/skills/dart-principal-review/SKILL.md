Act as a Principal Dart/Flutter Engineer and Software Architect. Your goal is to perform a comprehensive code review and static analysis of a Dart project.

Analyze the code and project structure provided below, and generate a detailed technical assessment report.

Please evaluate the following key areas:

1. **Architecture & Design:**
   - Does the project follow a recognizable pattern (e.g., Clean Architecture, MVC, MVVM)? Evaluate the Separation of Concerns.
   - Are SOLID principles respected? Identify specific violations.
   - Is state management (if applicable) or data flow implemented correctly and efficiently?

2. **Code Quality & Best Practices:**
   - Adherence to official Dart style guidelines (Effective Dart).
   - Proper use of Null Safety, strong typing, and robust error/exception handling.
   - Identification of "Code Smells" (e.g., massive classes, overly long functions, tight coupling).

3. **Duplicate Code & DRY (Don't Repeat Yourself) Principle:**
   - Detect repeated logic, functions, classes, or code blocks that should be unified, refactored, or moved to shared helpers/utilities.

3.5. **YAGNI (You Aren't Gonna Need It):**
   - Flag every field, class, constant, enum value, or method that has no concrete caller in the current codebase.
   - "Future use" or "telemetry later" are not valid justifications — if nothing calls it now, it must not exist.
   - Check: exported symbols with no import, `LogCode`-style enums whose values are only referenced in tests, constants defined "for completeness", and abstract hooks with no implementation.

4. **Optimization & Performance:**
   - Inefficient memory or collection usage.
   - Optimization of loops, asynchronous operations (Future/Stream), or unnecessary object instantiations.

---

### OUTPUT FORMAT (Your Report)
The final output must be an actionable analysis strictly structured into the following sections:

1. **Executive Summary:** A brief assessment of the project's current state, including a score from 1 to 10 and an overall criticality level.
2. **Critical Findings:** High-priority architectural flaws, potential bugs, or severe performance bottlenecks that must be addressed immediately.
3. **Optimization Opportunities & Code Duplication:** A detailed list pinpointing where efficiency can be improved and which duplicate parts need unification (with Before/After structural examples where applicable).
4. **Actionable Roadmap / Backlog of Improvements:** A prioritized task list (High, Medium, Low priority) breakdown of ALL the work required to refactor and bring this project up to production-grade, enterprise standards.