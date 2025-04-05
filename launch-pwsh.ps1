{
  "ACTIVE_MAIN_BRANCH": "main",
  "SKIP_SUBMODULES": true,
  "ENVIRONMENT_TESTS": [
    {
      "TASK_NAME": "Git LFS support",
      "EXPRESSION": {
        "TRY": "& git lfs version | Out-Null",
        "CATCH": "Write-Host 'Git LFS support seems to be unavailable.' -ForegroundColor Red; Write-Host 'Make sure that you have downloaded and installed:'; Write-Host '- Git LFS shell extension: ' -NoNewline; Write-Host 'https://git-lfs.github.com/' -ForegroundColor Cyan"
      }
    },
    {
      "TASK_NAME": "Git support",
      "EXPRESSION": {
        "TRY": "& git --version | Out-Null",
        "CATCH": "Write-Host 'Git support seems to be unavailable.' -ForegroundColor Red; Write-Host 'Make sure that you have downloaded and installed:'; Write-Host '- Git shell extension: ' -NoNewline; Write-Host 'https://git-scm.com/' -ForegroundColor Cyan"
      }
    }
  ]
}