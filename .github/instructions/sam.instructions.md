---
applyTo: '**/template.yaml'
---

- Use Globals section for common function properties (Runtime, MemorySize, Timeout, Tracing)
- Use `!Ref` and `!Sub` for resource references — no hardcoded ARNs or names
- One resource definition per logical unit — don't combine unrelated resources
- Tags on every resource: Environment, Service, Team
- IAM policies should follow least privilege — specific actions on specific resources
- Use `AWS::Serverless::Function` for Lambda (not raw `AWS::Lambda::Function`)
- API Gateway events use the `Api` event type with explicit Path and Method
- DynamoDB tables use `BillingMode: PAY_PER_REQUEST` for serverless-first
- Environment variables for config — never hardcode values that change per environment
