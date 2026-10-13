# Neovim Project Roots

- PHPactor searches upward from each PHP buffer for `composer.lock` and uses the TYPO3 project root. This gives extensions access to the project's TYPO3 classes and dependencies.
- Git tools use the nearest `.git` marker above the active file, so each extension uses its own repository.
- The window-local working directory follows the active file's repository and returns to Neovim's global working directory outside a repository.
- LazyGit resolves its root from the active buffer path. LazyVim's general root can follow PHPactor to the TYPO3 project root and miss a nested extension repository.
