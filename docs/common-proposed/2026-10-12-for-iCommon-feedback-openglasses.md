# For for-iCommon: ForIT Glasses rows in docs/feedback.md (FB-1, task 942E1773)

OpenGlasses can't write to for-iCommon, so these rows wait here for the for-iCommon lane.

## Feedback epics table

Add:

| App | Bundle | Feedback epic | Owner |
| --- | --- | --- | --- |
| ForIT Glasses | `com.forit.openglasses.dolores` | `08106FD9-AFFA-4041-90B5-F50B4BBD308F` | OpenGlasses |

The OpenGlasses lane created the epic itself, so `TaskLaneOwner` resolves to OpenGlasses.

## Adoption table

Replace the ForIT Glasses row with:

| App | Repo, path | Owner | Button | Credential | Ships by | State |
| --- | --- | --- | --- | --- | --- | --- |
| ForIT Glasses | OpenGlasses (`project.yml` and `Package.swift`, `from: 0.15.0`) | OpenGlasses | Settings, Feedback section (`FeedbackAccount.swift`), and shake once signed in | `TasksFeedbackKey`, minted after ForIT Sign-in (redirect `io.forit.glasses://oauth/callback`) the first time someone taps Send feedback; forgotten by Sign out of ForIT. Bernard itself still runs on its engine API key | `Scripts/mini-testflight.sh` | wired on main; one item sent from the Mini simulator landed as task 3D44E545 (screenshot did not upload, see below) |

DoloresWatch has no button: ForITCommon doesn't build for watchOS.

## Screenshot upload on the proof item

Task 3D44E545-7F9B-41C1-A500-BAA31AE3AF8C was created at 01:21:39.1Z on 2026-10-12 and its comment at
01:21:40.1Z, so the attachment POST between them failed within about a second. The task has
`attachmentsCount` 0, the Sent screen said "The screenshot didn't upload. The words did.", and the
description still says "Screenshot: attached", because it is written before the upload.
`TasksFeedbackSender.send` drops the attach error (`try?`), so the app can't tell why. The
for-Tasks request log for `POST /api/tasks/3d44e545-…/attachments` at that minute should have the status.
