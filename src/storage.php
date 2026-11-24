<?php
// Хранилище вложений капсул: Amazon S3 (ЛР4).
//
// Это единственный файл, который работает с загруженными файлами. Остальное приложение
// вызывает только три функции: storage_save(), storage_delete() и storage_stream().
// Файлы лежат в бакете S3 (переменная S3_BUCKET) под префиксом uploads/, на диске сервера
// ничего не хранится. Учётные данные SDK получает сам из роли EC2, привязанной к серверу
// (timecapsule-dev-app-role), ключи доступа в .env не нужны и не допускаются.

// Срок действия подписанной ссылки на скачивание, секунды (5 минут по заданию).
const STORAGE_LINK_TTL = 300;
// Префикс ключей в бакете: политика timecapsule-dev-app-s3 разрешает работу только с ним.
const STORAGE_PREFIX = 'uploads/';

// Клиент S3 создаётся один раз за запрос: static хранит его между вызовами.
function s3_client(): Aws\S3\S3Client
{
    static $client = null;
    if ($client === null) {
        $client = new Aws\S3\S3Client([
            'version' => 'latest',
            'region' => config('AWS_REGION', 'eu-central-1'),
        ]);
    }
    return $client;
}

// Имя бакета из настроек. Пустое значение означает ошибку конфигурации, а не ошибку пользователя.
function s3_bucket(): string
{
    $bucket = config('S3_BUCKET');
    if ($bucket === null) {
        throw new RuntimeException('S3_BUCKET is not set in .env');
    }
    return $bucket;
}

// Строка в storage/logs/storage.log. Если папка недоступна для записи, строка уходит в журнал PHP.
function storage_log(string $operation, Throwable $e): void
{
    $line = sprintf("[%s] %s: %s: %s\n", gmdate('Y-m-d\TH:i:s\Z'), $operation, get_class($e), $e->getMessage());
    $dir = ROOT_DIR . '/storage/logs';
    if (!is_dir($dir) || @file_put_contents($dir . '/storage.log', $line, FILE_APPEND | LOCK_EX) === false) {
        error_log(trim($line));
    }
}

// Ошибка хранилища: подробности в журнал, пользователю страница 502 без технических деталей.
// В abort() для кода 502 нет собственного заголовка, поэтому страница использует общий шаблон
// "Something went wrong" с нашим текстом и статусом 502.
function storage_fail(string $operation, Throwable $e): never
{
    storage_log($operation, $e);
    abort(502, 'The file storage is temporarily unavailable. Please try again later.');
}

// Сохраняет загруженный файл ($_FILES['...']) в S3 и возвращает случайное имя, например "3f9a...e1.png".
// Имя случайное, поэтому чужие имена файлов угадать нельзя.
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;
    // Тип содержимого определяется по самому файлу, а не по имени, которое прислал браузер.
    $contentType = mime_content_type($uploadedFile['tmp_name']) ?: 'application/octet-stream';

    try {
        s3_client()->putObject([
            'Bucket' => s3_bucket(),
            'Key' => STORAGE_PREFIX . $storedName,
            'SourceFile' => $uploadedFile['tmp_name'],
            'ContentType' => $contentType,
        ]);
    } catch (Throwable $e) {
        storage_fail('putObject ' . $storedName, $e);
    }
    return $storedName;
}

// Удаляет объект uploads/<имя>. Бакет версионируемый, поэтому объект получает маркер удаления,
// а предыдущая версия остаётся в бакете до правила жизненного цикла.
function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    // basename() гарантирует, что ключ не выйдет за пределы префикса uploads/.
    $name = basename($storedName);
    try {
        s3_client()->deleteObject([
            'Bucket' => s3_bucket(),
            'Key' => STORAGE_PREFIX . $name,
        ]);
    } catch (Throwable $e) {
        storage_fail('deleteObject ' . $name, $e);
    }
}

// Вместо отправки файла перенаправляет браузер (302) на подписанную ссылку S3 на 5 минут.
// $disposition: "inline" (показать в браузере) или "attachment" (скачать).
// Права пользователя на капсулу проверяет вызывающий код ДО этого вызова: S3 о пользователях не знает.
function storage_stream(string $storedName, string $mime, string $downloadName, string $disposition): void
{
    $name = basename($storedName);
    // В простом имени остаются только безопасные символы; полное имя в UTF-8 идёт в filename*.
    $asciiName = preg_replace('/[^A-Za-z0-9._ -]/', '_', $downloadName);
    $kind = $disposition === 'attachment' ? 'attachment' : 'inline';
    $contentDisposition = sprintf('%s; filename="%s"; filename*=UTF-8\'\'%s', $kind, $asciiName, rawurlencode($downloadName));

    try {
        $client = s3_client();
        $command = $client->getCommand('GetObject', [
            'Bucket' => s3_bucket(),
            'Key' => STORAGE_PREFIX . $name,
            'ResponseContentType' => $mime,
            'ResponseContentDisposition' => $contentDisposition,
        ]);
        $url = (string) $client->createPresignedRequest($command, '+' . STORAGE_LINK_TTL . ' seconds')->getUri();
    } catch (Throwable $e) {
        storage_fail('presign ' . $name, $e);
    }

    // Подписанный адрес отдаётся браузеру в том виде, в каком его вернул SDK: любое изменение ломает подпись.
    header('Location: ' . $url, true, 302);
    exit;
}
