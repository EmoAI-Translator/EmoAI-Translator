# Git Collaboration Guide

This document outlines the workflow and best practices for collaborating using Git in our projects.

---

## 1. Branching Strategy

- **Main Branch**
  - `main` or `master` is the stable branch.
  - Only fully tested and reviewed code is merged here.

- **Feature / Personal Branches**
  - Always create a new branch for your work.
  - Naming convention:
    ```text
    feature/<short-description>
    bugfix/<short-description>
    ```
  - Example:
    ```text
    feature/add-login-api
    bugfix/fix-typo-readme
    ```

- **Avoid committing directly to `main`.**  
  Work in your personal branch and merge via Pull Request (PR).

---

## 2. Issue-Based Workflow

- **Create Issues**
  - Each task, bug, or feature should have a corresponding GitHub/GitLab issue.
  - Reference the issue in your commits for traceability.

- **Branch from Issue**
  - Branch name can include issue number:
    ```text
    feature/123-login-api
    ```

---

## 3. Commit Conventions

- **Structure**
  ```text
  <type> <subject>
  ```
  - `type`:
    - `feat` ➔ New feature
    - `fix` ➔ Bug fix
    - `add` ➔ addition on feature
    - `refactor` ➔ Code refactoring
    - `style` ➔ Formatting changes (no code logic)
    - `test` ➔ Adding or updating tests
    - `chore` ➔ Maintenance tasks
  - `scope` (optional): module or file affected
  - `subject`: brief description in imperative mood

- **Examples**
  ```text
  feat: add JWT login API
  fix: correct button alignment on dashboard
  style: changed the UI of button
  ```

- **Reference Issues**
  ```text
  fix: correct button alignment on dashboard (#45)
  ```

---

## 4. Pull Request (PR) Guidelines

- Create a PR from your personal branch to `main`.
- Ensure:
  - Code is functional and tested.
  - Commits follow the convention.
  - PR description references related issues.
- Request review from at least one team member before merging.
- Merge only after approval.

---

## 5. Keeping Branches Updated

- **Always pull the latest changes before starting work**:
  ```bash
  git checkout main
  git pull origin main
  ```
- Then create your personal branch:
  ```bash
  git checkout -b feature/your-branch
  ```
- **Before merging or pushing your branch**, rebase with main:
  ```bash
  git checkout main
  git pull origin main
  git checkout feature/your-branch
  git rebase main
  ```
- Resolve any conflicts during rebase.

---

## 6. Additional Tips

- Write meaningful commit messages.
- Keep branches focused on a single task or issue.
- Delete feature branches after merging to keep repository clean.
- Run tests and linting before pushing code.

---

**By following this guide, we maintain a clean Git history and smooth collaboration workflow.**