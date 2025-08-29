# Contributing

## Prerequisites
- Python 3.11, Node 20, Flutter stable
- Docker (dev/test), docker-compose
- pre-commit installed (`pip install pre-commit`) and hooks (`pre-commit install`)

## Workflow
- Create a feature branch from `main`.
- Follow Conventional Commits (feat, fix, chore, docs, refactor, test).
- Ensure checks pass locally:
  - Backend: `pytest`, `black`, `flake8`, `isort`, `bandit`.
  - Frontend: `npm run lint`, `npm run build`.
  - Flutter: `flutter analyze`, `flutter test`.
- Open a PR; all CI checks must pass.
