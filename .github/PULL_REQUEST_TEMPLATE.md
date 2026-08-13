## Summary

<!-- What does this change and why? One PR = one logical change. -->

## Checklist

- [ ] `swift test` passes locally
- [ ] New user-facing strings exist in **both** `en.lproj` and `nb.lproj`
- [ ] New cleanup targets follow the registry conventions (CONTRIBUTING.md)
      and register **no user data**
- [ ] Targets that reach into a shared folder either register the
      sibling credentials/settings in `ExclusionRegistry` or declare the
      root reviewed-safe (the `rootsAreReviewed` test enforces this)
- [ ] Commits are atomic and follow Conventional Commits
