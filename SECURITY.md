# Security Policy

## Scope

RotationCore is a client-side World of Warcraft 3.3.5a addon. It does not make
network requests, does not execute user-supplied code (`loadstring` is not used;
profile/APL import uses a hand-written parser) and does not touch secure frames.

## Reporting a vulnerability

If you believe you found a security issue, please **do not open a public
issue**. Use GitHub's private vulnerability reporting:

- **Security → Report a vulnerability** on the repository page, or
- open a draft security advisory.

Please include:

- affected version (see the release tag / `## Version:` in the `.toc`),
- steps to reproduce,
- impact assessment.

We aim to acknowledge reports within a few days.
