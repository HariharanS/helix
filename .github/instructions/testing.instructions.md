---
applyTo: '**/Tests/**,**/tests/**,**/*Tests*,**/*Test*'
---

- Arrange-Act-Assert pattern for all tests
- Descriptive test names: `Method_Scenario_ExpectedResult`
- No mocking DynamoDB — use local DynamoDB for integration tests
- Pragmatic coverage — test behavior and business rules, not implementation details
- Tests must be independent — run in any order without affecting each other
- One assertion per logical concept (multiple asserts on the same object are fine)
- Use builder patterns or factories for test data, not inline construction of complex objects
- Integration tests go in a separate project/folder from unit tests
