use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub enum Language {
    English,
    Armenian,
    Russian,
}

impl Language {
    pub fn code(&self) -> &'static str {
        match self {
            Language::English => "en",
            Language::Armenian => "hy",
            Language::Russian => "ru",
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Language::English => "English",
            Language::Armenian => "Հայերեն (Armenian)",
            Language::Russian => "Русский (Russian)",
        }
    }
}

pub struct I18n {
    lang: Language,
    translations: HashMap<Language, HashMap<&'static str, &'static str>>,
}

impl I18n {
    pub fn new(lang: Language) -> Self {
        let mut translations = HashMap::new();

        let mut en = HashMap::new();
        en.insert("welcome_title", "Welcome to AWEOS");
        en.insert("welcome_subtitle", "Modern, native Rust & Wayland operating system.");
        en.insert("select_language", "Select System Language");
        en.insert("continue", "Continue");
        en.insert("back", "Back");
        en.insert("cancel", "Cancel");
        en.insert("install", "Install AWEOS");
        en.insert("reboot", "Restart System");
        en.insert("keyboard_title", "Keyboard Layout");
        en.insert("keyboard_subtitle", "Choose your preferred keyboard layout and variant.");
        en.insert("test_keyboard", "Test keyboard input here...");
        en.insert("network_title", "Network Connection");
        en.insert("network_offline", "Proceeding Offline (No active network required)");
        en.insert("install_type_title", "Installation Type");
        en.insert("erase_disk", "Erase disk and install AWEOS (Recommended)");
        en.insert("custom_part", "Manual / Custom Partitioning");
        en.insert("select_disk_title", "Select Target Storage Device");
        en.insert("user_account_title", "Create User Account");
        en.insert("full_name", "Full Name");
        en.insert("username", "Username");
        en.insert("hostname", "Computer Name (Hostname)");
        en.insert("password", "Password");
        en.insert("confirm_password", "Confirm Password");
        en.insert("timezone_title", "Timezone & Region");
        en.insert("summary_title", "Installation Summary");
        en.insert("confirm_install_warning", "WARNING: Selected disk will be partitioned and formatted!");
        en.insert("installing_title", "Installing AWEOS...");
        en.insert("complete_title", "Installation Complete!");
        en.insert("setup_welcome", "AWEOS First-Boot Setup");
        en.insert("setup_finish", "Finish & Launch AWEUI Desktop");
        translations.insert(Language::English, en);

        let mut hy = HashMap::new();
        hy.insert("welcome_title", "Բարի գալուստ AWEOS");
        hy.insert("welcome_subtitle", "Ժամանակակից Rust և Wayland օպերացիոն համակարգ:");
        hy.insert("select_language", "Ընտրեք համակարգի լեզուն");
        hy.insert("continue", "Շարունակել");
        hy.insert("back", "Հետ");
        hy.insert("cancel", "Չեղարկել");
        hy.insert("install", "Տեղադրել AWEOS");
        hy.insert("reboot", "Վերաբեռնել համակարգը");
        hy.insert("keyboard_title", "Ստեղնաշարի դասավորություն");
        hy.insert("keyboard_subtitle", "Ընտրեք ստեղնաշարի դասավորությունը:");
        hy.insert("test_keyboard", "Փորձարկեք ստեղնաշարի մուտքագրումը...");
        hy.insert("network_title", "Ցանցային միացում");
        hy.insert("network_offline", "Անցանց ռեժիմ (Ցանցային միացում չի պահանջվում)");
        hy.insert("install_type_title", "Տեղադրման տեսակը");
        hy.insert("erase_disk", "Մաքրել սկավառակը և տեղադրել AWEOS");
        hy.insert("custom_part", "Ձեռքով բաժանման կարգավորում");
        hy.insert("select_disk_title", "Ընտրեք թիրախային սկավառակը");
        hy.insert("user_account_title", "Ստեղծել օգտատիրոջ հաշիվ");
        hy.insert("full_name", "Անուն Ազգանուն");
        hy.insert("username", "Օգտանուն");
        hy.insert("hostname", "Համակարգչի անվանում (Hostname)");
        hy.insert("password", "Գաղտնաբառ");
        hy.insert("confirm_password", "Կրկնել գաղտնաբառը");
        hy.insert("timezone_title", "Ժամային գոտի և տարածաշրջան");
        hy.insert("summary_title", "Տեղադրման ամփոփում");
        hy.insert("confirm_install_warning", "ԶԳՈՒՇԱՑՈՒՄ. Ընտրված սկավառակը կձևաչափվի:");
        hy.insert("installing_title", "AWEOS-ի տեղադրում...");
        hy.insert("complete_title", "Տեղադրումն ավարտվեց:");
        hy.insert("setup_welcome", "AWEOS Առաջին գործարկման կարգավորում");
        hy.insert("setup_finish", "Ավարտել և գործարկել AWEUI Աշխատասեղանը");
        translations.insert(Language::Armenian, hy);

        let mut ru = HashMap::new();
        ru.insert("welcome_title", "Добро пожаловать в AWEOS");
        ru.insert("welcome_subtitle", "Современная операционная система на Rust и Wayland.");
        ru.insert("select_language", "Выберите язык системы");
        ru.insert("continue", "Продолжить");
        ru.insert("back", "Назад");
        ru.insert("cancel", "Отмена");
        ru.insert("install", "Установить AWEOS");
        ru.insert("reboot", "Перезагрузить систему");
        ru.insert("keyboard_title", "Раскладка клавиатуры");
        ru.insert("keyboard_subtitle", "Выберите раскладку клавиатуры.");
        ru.insert("test_keyboard", "Проверьте ввод с клавиатуры...");
        ru.insert("network_title", "Сетевое подключение");
        ru.insert("network_offline", "Автономный режим (сеть не требуется)");
        ru.insert("install_type_title", "Тип установки");
        ru.insert("erase_disk", "Очистить диск и установить AWEOS");
        ru.insert("custom_part", "Ручная разметка диска");
        ru.insert("select_disk_title", "Выберите целевой диск");
        ru.insert("user_account_title", "Создание учетной записи");
        ru.insert("full_name", "Полное имя");
        ru.insert("username", "Имя пользователя");
        ru.insert("hostname", "Имя компьютера (Hostname)");
        ru.insert("password", "Пароль");
        ru.insert("confirm_password", "Подтверждение пароля");
        ru.insert("timezone_title", "Часовой пояс и регион");
        ru.insert("summary_title", "Сводка установки");
        ru.insert("confirm_install_warning", "ВНИМАНИЕ: Выбранный диск будет форматирован!");
        ru.insert("installing_title", "Установка AWEOS...");
        ru.insert("complete_title", "Установка завершена!");
        ru.insert("setup_welcome", "Первоначальная настройка AWEOS");
        ru.insert("setup_finish", "Завершить и запустить AWEUI Desktop");
        translations.insert(Language::Russian, ru);

        Self { lang, translations }
    }

    pub fn set_language(&mut self, lang: Language) {
        self.lang = lang;
    }

    pub fn get_language(&self) -> Language {
        self.lang
    }

    pub fn t<'a>(&'a self, key: &'a str) -> &'a str {
        if let Some(map) = self.translations.get(&self.lang) {
            if let Some(val) = map.get(key) {
                return val;
            }
        }
        key
    }
}
