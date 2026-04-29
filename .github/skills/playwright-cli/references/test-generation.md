# Test Generation

Generate Playwright test code automatically as you interact with the browser.

## Match the binding to the repo's language

Detect the target language first (see SKILL.md "Before authoring tests"). Use the matching binding in the test files you write. Never mix.

`playwright-cli` emits TypeScript-style code in its output by default — treat it as a stand-in for the action and translate to the target language when writing the test file.

## How it works

Every action you perform with `playwright-cli` generates corresponding Playwright code. The action is the same across languages; only the syntax differs.

```bash
# Start a session
playwright-cli open https://example.com/login

# Take a snapshot to see elements
playwright-cli snapshot
# Output shows: e1 [textbox "Email"], e2 [textbox "Password"], e3 [button "Sign In"]

# Fill form fields - generates code automatically
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
```

The same three actions translate to each binding as follows.

### TypeScript

```typescript
import { test, expect } from '@playwright/test';

test('login flow', async ({ page }) => {
  await page.goto('https://example.com/login');
  await page.getByRole('textbox', { name: 'Email' }).fill('user@example.com');
  await page.getByRole('textbox', { name: 'Password' }).fill('password123');
  await page.getByRole('button', { name: 'Sign In' }).click();

  await expect(page).toHaveURL(/.*dashboard/);
});
```

### C# / .NET

```csharp
using Microsoft.Playwright;
using Microsoft.Playwright.NUnit;

[Parallelizable(ParallelScope.Self)]
[TestFixture]
public class LoginTests : PageTest
{
    [Test]
    public async Task LoginFlow()
    {
        await Page.GotoAsync("https://example.com/login");
        await Page.GetByRole(AriaRole.Textbox, new() { Name = "Email" }).FillAsync("user@example.com");
        await Page.GetByRole(AriaRole.Textbox, new() { Name = "Password" }).FillAsync("password123");
        await Page.GetByRole(AriaRole.Button, new() { Name = "Sign In" }).ClickAsync();

        await Expect(Page).ToHaveURLAsync(new Regex(".*dashboard"));
    }
}
```

### Python

```python
import re
from playwright.sync_api import Page, expect

def test_login_flow(page: Page):
    page.goto("https://example.com/login")
    page.get_by_role("textbox", name="Email").fill("user@example.com")
    page.get_by_role("textbox", name="Password").fill("password123")
    page.get_by_role("button", name="Sign In").click()

    expect(page).to_have_url(re.compile(r".*dashboard"))
```

### Java

```java
import com.microsoft.playwright.*;
import com.microsoft.playwright.options.AriaRole;
import static com.microsoft.playwright.assertions.PlaywrightAssertions.assertThat;

public class LoginTest {
    @Test
    void loginFlow() {
        page.navigate("https://example.com/login");
        page.getByRole(AriaRole.TEXTBOX, new Page.GetByRoleOptions().setName("Email")).fill("user@example.com");
        page.getByRole(AriaRole.TEXTBOX, new Page.GetByRoleOptions().setName("Password")).fill("password123");
        page.getByRole(AriaRole.BUTTON, new Page.GetByRoleOptions().setName("Sign In")).click();

        assertThat(page).hasURL(Pattern.compile(".*dashboard"));
    }
}
```

## Best Practices

### 1. Use semantic locators

Role-based locators are resilient across all bindings:

```typescript
// good — semantic, works the same way in every binding
await page.getByRole('button', { name: 'Submit' }).click();

// avoid — fragile CSS selectors
await page.locator('#submit-btn').click();
```

### 2. Explore before recording

Take snapshots to understand the page structure before recording actions:

```bash
playwright-cli open https://example.com
playwright-cli snapshot
# Review element structure
playwright-cli click e5
```

### 3. Add assertions manually

Generated code captures actions but not assertions. Add expectations using the matching binding's assertion syntax (`expect(...).toBe...` in TS, `Expect(...).To...Async` in C#, `expect(...).to_...` in Python).

### 4. Match the repo's existing test style

If the repo uses page objects, fixtures, or a specific naming convention, follow it. Generated code is a starting point — the final test must match the repo's patterns, not introduce new ones.
