# cloud-Autoscaler-infra-onEks
### Git Commands and GitHub Workflow

This section documents the Git commands used to manage feature branches, commit changes, push code to GitHub, and merge completed tasks into the `main` branch.

All commands should be executed from the repository root:

```bash
cd /home/testuser1/cloud-Autoscaler-infra-onEks
```

### 1. Check the current Git branch

```bash
git branch --show-current
```

Displays the branch currently checked out.

```bash
git branch
```

Lists local branches and highlights the current branch.

```bash
git branch -a
```

Lists local and remote-tracking branches.

### 2. Check repository status

```bash
git status
```

Displays the current branch, staged changes, unstaged modifications, and untracked files.

```bash
git status --short
```

Displays a compact summary of changes.

Common Git status indicators:

| Indicator | Meaning |
|---|---|
| `M` | Modified file |
| `A` | Added to staging |
| `??` | Untracked file |
| `D` | Deleted file |

In short status, the two character positions distinguish staged and unstaged changes.

### 3. Create feature branches

Task 2:

```bash
git switch -c feature/task-2-cicd
```

Task 3:

```bash
git switch -c feature/task-3-deployment
```

The `-c` option creates a new branch and switches to it.

To switch to an existing branch:

```bash
git switch feature/task-3-deployment
```

### 4. Stage specific project files

For Task 2:

```bash
git add task-2-cicd/
```

For Task 3:

```bash
git add task-3/
```

To stage a specific GitHub Actions workflow:

```bash
git add .github/workflows/task-3-validate.yml
```

Staging specific paths prevents unrelated project changes from being included accidentally.

Avoid using `git add .` when other tasks contain unfinished changes.

### 5. Inspect changes before committing

```bash
git diff
```

Shows unstaged changes.

```bash
git diff --cached
```

Shows staged changes.

```bash
git diff --cached --name-status
```

Lists staged filenames and their change types.

```bash
git diff --check
```

Checks unstaged changes for whitespace errors.

### 6. Commit changes

Task 2 example:

```bash
git commit -m "feat(task-2): add Go API and Docker CI/CD"
```

Task 3 implementation:

```bash
git commit -m "feat(task-3): add deployment validation and healthcheck scripts"
```

Task 3 GitHub Actions workflow:

```bash
git commit -m "ci(task-3): add deployment script validation workflow"
```

Commit messages should describe the changes clearly.

### 7. Push feature branches to GitHub

For the first push of a Task 2 branch:

```bash
git push -u origin feature/task-2-cicd
```

For the first push of Task 3:

```bash
git push -u origin feature/task-3-deployment
```

The `-u` option establishes upstream tracking.

For subsequent pushes:

```bash
git push
```

Or specify the branch:

```bash
git push origin feature/task-3-deployment
```

### 8. Create and merge pull requests

After pushing a feature branch:

1. Open the GitHub repository.
2. Create a pull request targeting `main`.
3. Review the changed files.
4. Check the GitHub Actions validation results.
5. Resolve any failures before merging.
6. Merge the pull request once approved.

Task 3 was merged through Pull Request #5.

Merge commit:

```text
4d4b77b2f832cdbaa5ce8e3103627c3759ada160
```

### 9. Synchronize local main after merging

First inspect the working tree:

```bash
git status --short
```

When it is safe to switch branches:

```bash
git switch main
```

Update the local branch:

```bash
git pull --ff-only origin main
```

The `--ff-only` option prevents Git from creating an unexpected merge commit.

If local modifications would be overwritten, preserve or resolve them before switching branches or pulling.

### 10. Inspect Git history

```bash
git log --oneline -10
```

Shows the ten most recent commits.

```bash
git log --oneline --graph --decorate --all
```

Displays commit history across branches.

```bash
git show --stat HEAD
```

Shows the files changed in the latest commit.

```bash
git remote -v
```

Displays the repository's configured remote URLs.

### 11. Useful Git debugging commands

```bash
git status
git branch -vv
git remote -v
git diff
git diff --cached
git log -5 --oneline
```

These commands help diagnose branch tracking, remote configuration, unexpected file changes, and commit history.

For remote connectivity:

```bash
git ls-remote origin
```

Checks whether Git can communicate with the configured remote repository.

For Git identity configuration:

```bash
git config --global --list
```

Displays global Git configuration.

```bash
git config --get user.name
git config --get user.email
```

Displays the effective Git identity for the current repository.

### 12. Recommended Git workflow for future tasks

```bash
# Check the current state
git status --short
git branch --show-current

# Update main when the working tree is safe
git switch main
git pull --ff-only origin main

# Create a new task branch
git switch -c feature/task-4-kubernetes

# Stage only the relevant task
git add task-4/

# Review staged files
git diff --cached --name-status

# Commit the changes
git commit -m "feat(task-4): add Kubernetes and autoscaling configuration"

# Push to GitHub
git push -u origin feature/task-4-kubernetes
```

After pushing, create a pull request targeting `main` and verify all required GitHub Actions checks before merging.

**Important:** These commands manage source code in Git. They do not provision AWS infrastructure or deploy the application to EKS.