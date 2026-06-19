# Changelog

This changelog lists **breaking changes only** — chart versions that require
operator action beyond a routine `helm upgrade`, or that drop compatibility with
older image tags. Non-breaking changes (new options, fixes, defaults) are not
recorded here; see the git history for the full picture.

## 0.2.0

**Requires app-server image `0.1.628` or newer (or `latest`).**

The standalone query-engine workload has been removed. Its functionality is now
built directly into the app-server image as of tag `0.1.628`. Chart `0.2.0`
no longer deploys the query-engine pod and assumes the app-server provides it.

Action required:

- Ensure `images.appServer.tag` is `0.1.628` or newer, or `latest`. The chart
  hard-fails at render time (`helm install`/`upgrade`/`template`) if it detects
  a pinned semver tag older than `0.1.628`. Non-semver tags (`latest`, branch
  names, digests) are not checked — pinning those is your responsibility.
- No data migration is needed; the query-engine was stateless.
