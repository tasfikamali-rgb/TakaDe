# 5. Generate the Xcode project with XcodeGen

Status: Accepted (2026-11-11)

`project.yml` is the source of truth and `TakaDe.xcodeproj` is generated and git-ignored.
This avoids merge conflicts in `project.pbxproj` and keeps the project readable in review.
Run `xcodegen generate` after pulling.
