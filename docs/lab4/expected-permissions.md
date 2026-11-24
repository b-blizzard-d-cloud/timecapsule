# ЛР4, задание 8. Ожидаемые результаты проверки прав (заполнено до запуска команд)

Состояние на момент записи: версионирование бакета включено; политика бакета `DenyInsecureTransport` действует; политика `timecapsule-dev-app-s3` версии `v1` (`s3:ListBucket` с условием `s3:prefix` = `uploads/*`; `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` на `uploads/*`).

| № | Команда | Ожидаю | Правило, которое должно сработать |
| --- | --- | --- | --- |
| 1 | `aws s3 cp test.txt s3://$BUCKET/uploads/test.txt` | разрешено | разрешение в политике приложения (`s3:PutObject`) |
| 2 | `aws s3 ls s3://$BUCKET/uploads/` | разрешено | разрешение в политике приложения (`s3:ListBucket`, `prefix=uploads/`) |
| 3 | `aws s3 ls s3://$BUCKET` | AccessDenied | неявный запрет (пустой префикс не подходит под условие) |
| 4 | `aws s3 cp s3://$BUCKET/uploads/photo.txt -` | разрешено | разрешение в политике приложения (`s3:GetObject`) |
| 5 | `aws s3 ls s3://$BUCKET/backups/` | AccessDenied | неявный запрет (`prefix=backups/` не подходит под условие) |
| 6 | `aws s3 cp test.txt s3://$BUCKET/backups/test.txt` | AccessDenied | неявный запрет (ARN `backups/*` не входит в разрешённый ресурс) |
| 7 | `aws s3api list-object-versions --bucket $BUCKET --prefix uploads/` | AccessDenied | неявный запрет (нужно действие `s3:ListBucketVersions`, его нет в политике) |
| 8 | `aws s3api delete-object --bucket $BUCKET --key uploads/test.txt --version-id <VersionId>` | AccessDenied | неявный запрет (нужно `s3:DeleteObjectVersion`, его нет в политике) |
| 9 | `aws s3 rm s3://$BUCKET/uploads/test.txt` | разрешено | разрешение в политике приложения (`s3:DeleteObject` без версии создаёт маркер удаления) |
| 10 | `aws s3 ls s3://$BUCKET/uploads/ --endpoint-url http://s3.eu-central-1.amazonaws.com` | AccessDenied | явный запрет в политике бакета (`aws:SecureTransport=false`) |
