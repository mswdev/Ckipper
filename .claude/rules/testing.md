# Testing

## Philosophy

Tests are **documentation** that happens to be executable. A test should read like a specification of behavior.

## Structure: Arrange -> Act -> Assert

Separate the three phases with blank lines:

```python
class TestOrderProcessor:
    def test_creates_order_for_valid_request(self):
        request = RequestFixture.valid()
        processor = build_order_processor()

        order = processor.submit(request)

        assert order.status == OrderStatus.PENDING
        assert order.request_id == request.id

    def test_rejects_invalid_requests(self):
        request = RequestFixture.invalid()
        processor = build_order_processor()

        with pytest.raises(InvalidRequestError):
            processor.submit(request)
```

## What to Test

- **Processors and business logic** — Always. This is the core of the system.
- **Utility/helper functions** — Always. They're pure and easy to test.
- **Financial calculations** — Always. Money math must be bulletproof.
- **Entry points / handlers** — Integration tests for the happy path and key error cases.
- **Observable behavior, not implementation** — When testing components or modules with internal state, assert on the externally visible outcomes, not on private structure.

## What NOT to Test

- Simple getters/setters or data classes with no logic.
- Framework boilerplate (middleware wiring, route config, loader setup).
- Third-party library behavior.

## Test Doubles

Prefer **hand-written fakes** over mocking libraries. Fakes are simpler, more readable, and catch interface drift at compile time.

## Quality Gates

**Before committing, ALWAYS run** the project's verification commands (build / test / lint / typecheck — whichever apply).

<!-- Add per-package gates as needed. Example:
**Per-package gates:**
- **api:** `npm run typecheck && npm run test && npm run lint`
- **webapp:** `npm run test && npm run lint`
-->
