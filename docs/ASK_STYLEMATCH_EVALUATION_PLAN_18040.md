# Ask StyleMatch evaluation plan — Build 1.8040

## Deterministic local coverage

- manual Fashion Stylist routing permits only selected scopes;
- completed scan score, classification, and summary retain exact authority;
- Writing Assist rejects absent selected text and excludes unrelated context;
- automatic multi-intent questions require clarification;
- current research remains unavailable without a silent network fallback;
- provider descriptors require `store: false`, no background work, and no
  conversation reference;
- the local provider returns unavailable rather than contacting a provider.

## Required future server evaluation

Before enabling a provider, measure grounded answer quality by specialty,
citations/freshness, unsafe-advice refusal quality, prompt-injection handling,
cross-account isolation, consent revocation, deletion propagation, rate and
cost ceilings, degraded-provider behavior, and no-tool/no-network behavior
when a capability is not explicitly granted.

No live model evaluation, web search, provider key, or user content is used by
this local checkpoint.
