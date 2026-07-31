# Security Policy

## Reporting a Vulnerability

We take security issues seriously. If you discover a security vulnerability in Cloudrs, **please do not open a public GitHub issue**.

Instead, report it privately by emailing:

**wangxian@dreamflytech.com**

Please include the following in your report so we can reproduce and assess the issue quickly:

- A description of the vulnerability and its potential impact.
- The affected version (see the app version in `AppScope/app.json5` or the latest [release tag](https://github.com/Cloudrs/Cloudrs-ohos/tags)).
- Step-by-step reproduction instructions, including any relevant server (Cloudreve) version and HarmonyOS version.
- A proof-of-concept or exploit, if available.

## Response

We will acknowledge receipt of your report within **3 business days** and aim to send an initial assessment within **7 days**. We will keep you informed of remediation progress and coordinate a public disclosure timeline with you once a fix is available.

We kindly request that you:

- Give us reasonable time to investigate and remediate before any public disclosure.
- Avoid accessing or modifying data that does not belong to you, and test only against your own Cloudreve deployments.

## Scope

This policy covers the Cloudrs client and the `cloudreve-api-native` submodule. Vulnerabilities in the upstream [Cloudreve server](https://github.com/cloudreve/Cloudreve) should be reported to its maintainers directly.

## Out of Scope

- Issues in third-party dependencies — please report those upstream.
- Self-inflicted misconfiguration of your own Cloudreve deployment.
- Findings from automated scanners without a demonstrated, reproducible impact.
