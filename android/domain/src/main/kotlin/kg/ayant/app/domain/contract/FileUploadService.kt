package kg.ayant.app.domain.contract


/**
 * Загрузка файла (фото заведения, PDF-меню) и получение публичной ссылки.
 *
 * Вынесено из `ui/host/UploadButton.kt`: раньше Compose-компонент сам дёргал
 * `FirebaseStorage`, из-за чего UI зависел от SDK и не работал в оффлайн-режиме.
 * Зеркалит `ImageUpload.swift` на iOS (там загрузка идёт в Cloudinary).
 */
interface FileUploadService {
    /**
     * Загружает файл по [uri] (строковый URI — домен не знает про `android.net.Uri`) в папку [folder]. Возвращает публичный URL либо `null`,
     * если загрузка не удалась — вызывающий показывает ошибку.
     *
     * @param mimeType MIME-тип: изображение или "application/pdf" — определяет расширение.
     */
    suspend fun upload(uri: String, folder: String, mimeType: String): String?
}

/** Оффлайн-режим: загружать некуда. */
