/**
 * Генератор Google Формы: "Добавить бизнес в приложение"
 * Анкета для бизнеса (заявка на добавление в приложение — Yelp для Центральной Азии).
 *
 * КАК ИСПОЛЬЗОВАТЬ:
 * 1. Откройте https://script.google.com → New project (Новый проект).
 * 2. Удалите пример кода, вставьте весь этот файл.
 * 3. Нажмите Run (Запустить) → функция createBusinessForm.
 * 4. Разрешите доступ к аккаунту (Authorize).
 * 5. В логах (View → Logs) появятся ссылки на форму:
 *    - EDIT URL   — для редактирования
 *    - LIVE URL   — для отправки бизнесу (заполнение)
 */

function createBusinessForm() {
  var form = FormApp.create('Добавить бизнес в приложение Ayant — заявка');

  form.setDescription(
    'Заполните эту анкету, чтобы добавить ваш бизнес в приложение. ' +
    'Мы проверим информацию и опубликуем карточку заведения. ' +
    'Поля со звёздочкой обязательны для заполнения.'
  );
  form.setProgressBar(true);
  form.setCollectEmail(false);

  // 1. Название бизнеса
  form.addTextItem()
    .setTitle('Название бизнеса')
    .setRequired(true);

  // 2. Категория
  form.addListItem()
    .setTitle('Категория')
    .setChoiceValues([
      'Ресторан',
      'Кафе',
      'Бар / Паб',
      'Кофейня',
      'Фаст-фуд',
      'Чайхана',
      'Пекарня'
    ])
    .setRequired(true);

  // 3. Краткое описание
  form.addParagraphTextItem()
    .setTitle('Краткое описание бизнеса')
    .setHelpText('Чем вы занимаетесь, что отличает вас от других (2–4 предложения).')
    .setRequired(true);

  // 4. Город
  form.addListItem()
    .setTitle('Город')
    .setChoiceValues([
      'Бишкек',
      'Другой'
    ])
    .setRequired(true);

  // 5. Адрес
  form.addTextItem()
    .setTitle('Адрес (улица, дом, ориентир)')
    .setRequired(true);

  // 6. Телефон
  var phone = form.addTextItem()
    .setTitle('Контактный телефон')
    .setRequired(true);
  var phoneValidation = FormApp.createTextValidation()
    .setHelpText('Введите корректный номер телефона.')
    .requireTextMatchesPattern('^[+0-9\\s\\-\\(\\)]{6,}$')
    .build();
  phone.setValidation(phoneValidation);

  // 7. Email
  var email = form.addTextItem()
    .setTitle('Email для связи');
  var emailValidation = FormApp.createTextValidation()
    .setHelpText('Введите корректный email.')
    .requireTextIsEmail()
    .build();
  email.setValidation(emailValidation);

  // 8. Сайт и соцсети
  form.addParagraphTextItem()
    .setTitle('Веб-сайт и соцсети')
    .setHelpText('Ссылки на сайт, Instagram, 2ГИС и т.д. (каждая с новой строки).');

  // 9. Часы работы
  form.addParagraphTextItem()
    .setTitle('Часы работы')
    .setHelpText('Например: Пн–Пт 09:00–22:00, Сб–Вс 10:00–23:00. Укажите выходные, если есть.')
    .setRequired(true);

  // 10. Ценовая категория
  form.addMultipleChoiceItem()
    .setTitle('Ценовая категория (средний чек)')
    .setChoiceValues([
      '$ — эконом',
      '$$ — средний',
      '$$$ — выше среднего',
      '$$$$ — премиум'
    ])
    .setRequired(true);

  // 12. Способы оплаты
  form.addCheckboxItem()
    .setTitle('Принимаемые способы оплаты')
    .setChoiceValues([
      'Наличные',
      'Банковская карта',
      'ELQR',
      'Банковский перевод'
    ])
    .setRequired(true);

  // 13. Фотографии (ссылки)
  form.addParagraphTextItem()
    .setTitle('Ссылки на фотографии')
    .setHelpText('Вставьте ссылки на фото (Google Drive, облако и т.д.). ' +
      'Логотип, интерьер, витрина, меню — что есть.');

  // 14. Контактное лицо
  form.addTextItem()
    .setTitle('Контактное лицо (имя)')
    .setRequired(true);

  // 15. Должность
  form.addTextItem()
    .setTitle('Должность контактного лица')
    .setHelpText('Например: владелец, управляющий, менеджер.');

  // 16. Согласие
  var consent = form.addCheckboxItem();
  consent.setTitle('Согласие');
  consent.setChoiceValues([
    'Я подтверждаю, что информация верна, и даю согласие на её публикацию и обработку.'
  ]);
  consent.setRequired(true);

  // Ссылки
  Logger.log('EDIT URL: ' + form.getEditUrl());
  Logger.log('LIVE URL: ' + form.getPublishedUrl());
}
