# Contributing

Thanks for your interest in MacPocket.

## Setup

You need an Apple Silicon Mac with the macOS and Xcode versions required by
`Package.swift`. See [Getting started](docs/development/getting-started.md).

```sh
make build
make verify   # app and package tests + localization check; must pass before you push
```

## Workflow

1. Open an issue for anything larger than a small fix so the approach can be agreed.
2. Branch from `main` using `feature/`, `fix/`, `chore/`, `refactor/` or `docs/`.
3. Add tests with the change. Bug fixes start with a failing regression test.
4. Add or update English translations for any new text
   ([Localization](docs/development/localization.md)).
5. Keep documentation in step with the code ([docs/README.md](docs/README.md)).
6. Use [Conventional Commits](https://www.conventionalcommits.org/), for example
   `fix(clipboard): avoid rewriting unchanged history`.
7. Open a pull request describing the user-visible change and how you verified it.

Read the [conventions](docs/architecture/conventions.md) first. Changes that add a
dependency, a process or a privileged operation need a
[decision record](docs/decisions/README.md) and a security review of the new surface.
