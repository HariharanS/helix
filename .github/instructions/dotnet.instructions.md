---
applyTo: '**/*.cs'
---

- Use C# 12 features (primary constructors, collection expressions) when targeting .NET 8+
- Result pattern for domain errors — do not throw exceptions for expected business failures
- Async all the way — no `.Result`, `.Wait()`, or `GetAwaiter().GetResult()`
- Nullable reference types enabled — handle nullability explicitly
- Domain logic in `Domain/` must never reference AWS SDK or infrastructure packages
- Infrastructure implements interfaces defined in `Contracts/`
- One Lambda handler class per file in `Functions/`
- Use dependency injection — register services in the DI container, not static instances
- Naming: PascalCase for public members, _camelCase for private fields
