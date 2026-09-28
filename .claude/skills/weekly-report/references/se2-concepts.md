# SE2 Concept Guide — extracted reference

Full text content of `SE2-CONCEPT-GUIDE.docx` (repo root), extracted so the
weekly report can cite concepts without re-parsing the .docx every week.

**Cite these definitions in the instructor's own words**, then explain how the
Ziren code matches. If the guide and this file ever disagree, the .docx wins —
re-extract it with `inspect_docx.py`.

## Contents

1. [Design patterns](#1-design-patterns) — creational, structural, behavioral
2. [Refactoring & code smells](#2-refactoring--code-smells)
3. [Software testing concepts](#3-software-testing-concepts)
4. [Configuration management & CI/CD](#4-configuration-management--cicd)
5. [Software maintenance types](#5-software-maintenance-types)
6. [Additional SE2 principles](#6-additional-se2-principles)
7. [Quick reference — "if you did this, the concept is…"](#7-quick-reference)

---

## 1. Design patterns

Reusable solutions to common problems in software design, categorized into
creational, structural, and behavioral.

### Creational (object creation)

| Pattern | What it does | When to use | Guide's example |
|---|---|---|---|
| **Factory** | Creates objects without exposing the creation logic to the client. | Multiple types of objects to create; want to centralize creation logic. | Creating different types of users (Admin, Faculty, Student) using a `UserFactory`. |
| **Builder** | Constructs complex objects step by step. | An object has many optional parameters or a complex construction process. | Building a `Schedule` object with room, time, equipment, attendees. |
| **Singleton** | Ensures only one instance of a class exists. | Exactly one instance needed (database connection, logger). | A single `DatabaseConnection` instance shared across the entire application. |

### Structural (class/object composition)

| Pattern | What it does | When to use | Guide's example |
|---|---|---|---|
| **Adapter** | Allows incompatible interfaces to work together. | Integrating a third-party library with a different interface. | Wrapping a Google Calendar API with a `CalendarAdapter`. |
| **Decorator** | Adds responsibilities to an object dynamically without changing its structure. | Adding functionality without modifying existing code. | Adding logging, caching, or error handling to a service. |
| **Proxy** | Provides a placeholder for another object to control access to it. | Lazy loading, access control, logging, caching. | A `CachingProxy` storing API responses in Redis. |
| **Repository** | Mediates between the domain and data mapping layers, acting like an in-memory collection of objects. | Abstracting database operations; making testing easier. | A `UserRepository` handling all database queries for users. |

### Behavioral (communication between objects)

| Pattern | What it does | When to use | Guide's example |
|---|---|---|---|
| **Strategy** | Defines a family of algorithms, encapsulates each, makes them interchangeable. | Multiple ways to perform an operation; avoiding complex if-else chains. | Different validation strategies for scheduling. |
| **Observer** | One-to-many dependency: when one object changes state, all dependents are notified. | Notifying multiple objects about state changes. | Notifying users when a booking is created, updated, cancelled. |
| **Command** | Encapsulates a request as an object. | Parameterizing, queueing, or logging requests. | Booking actions (create, update, cancel) as command objects. |
| **Middleware** | A chain of components that process requests before reaching the main handler. | Cross-cutting concerns (authentication, logging, validation). | Express middleware for JWT verification, logging, error handling. |

## 2. Refactoring & code smells

Refactoring improves the internal structure of code without changing its
external behavior.

| Code smell | Definition | Refactoring technique |
|---|---|---|
| **Long Method** | A method that is too long and does too many things. | Extract Method — break it into smaller, focused methods. |
| **God Class / Large Class** | A class that knows and does too much. | Extract Class — move related responsibilities to new classes. |
| **Duplicated Code** | The same code appears in multiple places. | Extract Method — create a shared method or function. |
| **Feature Envy** | A method more interested in another class's data than its own. | Move Method — move it to the class it belongs to. |
| **Long Parameter List** | A method has too many parameters. | Introduce Parameter Object. |
| **Switch Statements / Complex Conditionals** | Long chains of if-else or switch. | Replace Conditional with Polymorphism, or use Strategy. |

## 3. Software testing concepts

### Test doubles

A Test Double is a "stand-in" that replaces a real component during testing.

| Type | What it does | When to use |
|---|---|---|
| **Stub** | Returns fixed, hard-coded values. | A simple replacement returning predictable data. |
| **Fake** | A lightweight implementation that behaves like the real thing but simplified. | A working replacement (in-memory database instead of a real one). |
| **Mock** | A sophisticated double that can verify interactions and set expectations. | Verifying that methods were called with specific parameters. |
| **Spy** | Wraps a real object and tracks how it is used. | Verifying interactions without fully mocking an object. |

### Testing approaches

| Concept | Definition |
|---|---|
| **Unit Testing** | Testing individual components or functions in isolation. |
| **Integration Testing** | Testing how different components work together. |
| **Test-Driven Development (TDD)** | Writing tests before code (Red-Green-Refactor). |
| **In-Memory Repository** | A repository storing data in memory for fast, isolated testing. |

## 4. Configuration management & CI/CD

| Concept | Definition |
|---|---|
| **Configuration Management** | Managing environment variables, settings, and dependencies consistently across development, testing, and production. |
| **CI/CD Pipeline** | Continuous Integration (automatically running tests on code changes) and Continuous Delivery (automatically deploying to staging/production). |
| **Environment Variables** | Storing configuration values (API keys, database URLs) outside of code for security and flexibility. |
| **Dependency Management** | Using `package.json`, `requirements.txt`, etc. to lock exact library versions. |

## 5. Software maintenance types

Classify maintenance-related problems correctly — most Ziren problems are
**Corrective**, and pairing that with a design concept makes a stronger entry
than either alone.

| Type | Definition | Guide's example |
|---|---|---|
| **Corrective** | Fixing bugs and errors discovered after the software is in use. | Fixing a server crash caused by unhandled promise rejections. |
| **Adaptive** | Modifying software to accommodate changes in the environment (new OS, hardware, regulations). | Updating the system for a new version of PostgreSQL. |
| **Perfective** | Improving performance, functionality, or maintainability. | Reducing response time from 12s to 2s using caching. |
| **Preventive** | Making changes to prevent future problems. | Adding audit logging to prevent accountability issues. |

## 6. Additional SE2 principles

| Concept | Definition |
|---|---|
| **SOLID Principles** | Five design principles for maintainable, scalable code (Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion). |
| **Single Responsibility Principle (SRP)** | A class should have only one reason to change. |
| **Separation of Concerns** | Different parts of the system should handle different concerns (UI, business logic, data access). |
| **Dependency Injection** | Passing dependencies (like repositories) into a class rather than creating them inside the class. |
| **Normalization** | Organizing database tables to reduce redundancy and improve integrity (e.g. 3NF). |

## 7. Quick reference

The guide's own mapping table. Start here when picking a concept — it keeps
the citation honest instead of reaching for whatever sounds most advanced.

| If you did this… | The SE2 concept is… |
|---|---|
| Created a class to handle object creation | Factory Pattern |
| Built an object step by step with many options | Builder Pattern |
| Ensured only one instance of a class exists | Singleton Pattern |
| Wrapped an incompatible API | Adapter Pattern |
| Added logging/error handling without changing the original class | Decorator Pattern |
| Added caching to speed up slow operations | Proxy Pattern |
| Abstracted database operations | Repository Pattern |
| Replaced if-else chains with interchangeable algorithms | Strategy Pattern |
| Notified other objects about state changes | Observer Pattern |
| Broke a large method into smaller ones | Refactoring — Extract Method |
| Used an in-memory database for testing | Test Double — Fake |
| Verified that a method was called correctly | Test Double — Mock |
| Fixed a bug found after deployment | Corrective Maintenance |
| Updated code for a new database version | Adaptive Maintenance |
| Improved system performance | Perfective Maintenance |
| Added logging to prevent future issues | Preventive Maintenance |

---

## Ziren-specific notes

Concepts that keep recurring in this codebase, and where they actually live —
useful for grounding a citation in real code rather than a generic definition:

- **Singleton** — `ziren_backend/app/db/supabase_client.py` caches one
  service-role client; `app/core/rate_limit.py` owns the single shared
  slowapi `Limiter` (three module-local Limiters used to exist, which is what
  made rate-limit tests fail spuriously).
- **Repository** — `ziren_mobile/lib/features/*/data/*_repository.dart`
  isolates every HTTP call per feature.
- **Strategy** — the rubric engine: rules are data (JSON configs per agency),
  not branching code, so severity policy is interchangeable per agency.
- **Test Double** — `rubric_service.evaluate(..., db=None)` takes an injected
  client precisely so tests can pass a mock.
- **Separation of Concerns** — routers / services / models / db layering in
  `ziren_backend/app/`.
- **Configuration Management** — `.env` + `.env.example` on the backend,
  `dart_defines.json` on mobile, `NEXT_PUBLIC_API_BASE_URL` on the dashboard.
- **Dependency Injection** — FastAPI `Depends(...)` in `app/core/dependencies.py`.
