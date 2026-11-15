# Обоснование ограничений

Схема `dunaev_food`.

## Enum типы

| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | активен, неактивен | BR-4.3 |
| `product_status` | доступно, нет_в_наличии, архив | BR-5.5 |
| `courier_status` | свободен, занят, на_доставке, уволен | BR-6.2 |
| `order_status` | создан, готовится, в_доставке, доставлен, отменён | BR-7.7 |
| `order_pay_status` | ожидает, оплачен, ошибка | BR-7.9 |
| `payment_status` | успех, ошибка, в_обработке | BR-8.2 |
| `payment_type` | карта, наличные, безнал | BR-8.2 |
| `review_entity_type` | блюдо, ресторан, заказ | BR-9.1 |

Значения взяты из BR без изменений.

---

## Ловушки

### Ловушка 1: `payment` неполная сущность

**Какие атрибуты добавил в `payment` и почему** (BR-8.2):

```
payment_type          тип оплаты (BR-8.2)
amount                сумма попытки (BR-8.2, BR-8.4)
transaction_id        идентификатор транзакции от провайдера, уникальный (BR-8.2, BR-8.3)
transaction_timestamp дата и время транзакции (BR-8.2)
status                статус попытки (BR-8.2)
```

**Где хранится тип оплаты, `payment` или `order`** (BR-8.6):

```
В payment. По BR-8.6 тип относится к попытке оплаты, и у одного заказа могут быть
попытки разных типов.
```

### Ловушка 2: `order.address_id` принадлежит клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**

```
Составной FK:
FOREIGN KEY (client_id, address_id) REFERENCES client_address (client_id, address_id)
Заказ нельзя создать на адрес, которого нет у этого клиента в client_address.
```

### Ловушка 3: `order_structure` один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**

```
Триггер order_structure_check на INSERT и UPDATE в order_structure. Он сравнивает
ресторан блюда с рестораном заказа и выдаёт ошибку, если они разные.
Составной FK не делал, потому что для него пришлось бы хранить restaurant_id
в order_structure, а он зависит только от order_id, это нарушает 2НФ.
Ещё два триггера запрещают менять restaurant_id у заказа и у блюда, если после
этого состав заказа станет неправильным.
```

### Ловушка 4: `review` полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**

```
Полиморфизм, как в erd.md (entity_type + entity_id). Обычный FK поставить нельзя,
потому что entity_id ссылается на три разные таблицы.
Проверку делает триггер review_validate:
  заказ    entity_id = order_id
  ресторан entity_id = restaurant_id этого заказа
  блюдо    блюдо есть в order_structure этого заказа
Составной FK (order_id, client_id) на "order" проверяет, что заказ принадлежит
клиенту (BR-9.2).
```

---

## CHECK ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `address` | `street`, `house_number` | не пустая строка | BR-3.1, BR-11.3 | улица и дом обязательны |
| `address` | `apartment_office` | NULL или не пустая строка | BR-3.2 | квартира необязательна, но пустой строки быть не должно |
| `client` | `login` | не пустая строка | BR-2.1, BR-11.3 | логин обязателен |
| `client` | `password` | `~ '^[0-9a-f]{32}$'` | BR-2.3 | пароль хранится как MD5 |
| `client` | `phone_number` | `~ '^\+7[0-9]{10}$'` | BR-2.1, BR-2.2 | один формат номера, иначе UNIQUE можно обойти |
| `restaurant` | `restaurant_name` | не пустая строка | BR-4.1, BR-11.3 | название обязательно |
| `restaurant` | `work_end` | `work_end > work_start` | BR-4.4 | закрытие позже открытия |
| `restaurant` | `rating` | `BETWEEN 0 AND 5` | BR-4.2 | диапазон рейтинга |
| `product_category` | `product_category_name` | не пустая строка | BR-5.7 | у категории есть название |
| `product` | `product_name` | не пустая строка | BR-5.2, BR-11.3 | название обязательно |
| `product` | `price` | `price >= 0` | BR-5.3 | цена неотрицательна |
| `product` | `rating` | `BETWEEN 0 AND 5` | BR-5.4 | диапазон рейтинга |
| `product` | `photo_url` | NULL или не пустая строка | BR-5.6 | фото необязательно |
| `courier` | `fio` | не пустая строка | BR-6.1, BR-11.3 | ФИО обязательно |
| `courier` | `phone_number` | `~ '^\+7[0-9]{10}$'` | BR-6.1 | один формат номера |
| `courier` | `coefficient` | `BETWEEN 0.1 AND 0.5` | BR-6.4 | диапазон коэффициента |
| `courier` | `dismissal_date` | `status <> 'уволен' OR dismissal_date IS NOT NULL` | BR-6.3 | у уволенного есть дата увольнения |
| `courier` | `dismissal_date` | `dismissal_date >= hire_date` | BR-6.1, BR-6.3 | уволить раньше найма нельзя |
| `courier_pay` | `month` | `BETWEEN 1 AND 12` | BR-10.1 | номер месяца |
| `courier_pay` | `amount` | `amount >= 0` | BR-10.4 | зарплата неотрицательна |
| `courier_pay` | `coefficient_used` | `BETWEEN 0.1 AND 0.5` | BR-6.4 | тот же диапазон, что у курьера |
| `order` | `order_amount` | `order_amount >= 0` | BR-7.10 | стоимость блюд неотрицательна |
| `order` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | минимальная сумма заказа |
| `order` | `delivery_timestamp` | `delivery_timestamp >= order_timestamp` | BR-7.13 | доставка не раньше создания |
| `order` | `delivery_timestamp` | `status <> 'доставлен' OR delivery_timestamp IS NOT NULL` | BR-7.12 | у доставленного заказа есть время доставки |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | количество положительное |
| `payment` | `amount` | `amount >= 1000` | BR-8.4, BR-7.11 | сумма оплаты равна сумме заказа |
| `payment` | `transaction_id` | не пустая строка | BR-8.3 | идентификатор обязателен |
| `review` | `rating` | `BETWEEN 1 AND 5` | BR-9.4 | диапазон рейтинга отзыва |
| `review` | `photo_url` | NULL или не пустая строка | BR-9.3 | фото необязательно |

Правила, которые нельзя записать через CHECK, сделаны триггерами:

| Триггер | BR | Что делает |
|---|---|---|
| `order_structure_check` | BR-7.3 | блюдо из ресторана заказа |
| `order_restaurant_guard`, `product_restaurant_guard` | BR-7.3 | нельзя сменить ресторан, если состав заказа станет неправильным |
| `review_validate` | BR-9.2 | отзыв только на то, что есть в заказе |
| `payment_amount_check` | BR-8.4 | сумма оплаты равна `order.total_amount` |
| `order_pay_status_refresh` | BR-8.7 | пересчитывает `order.pay_status` по попыткам |
| `rating_change` | BR-9.6, BR-9.7 | пересчитывает рейтинг блюда и ресторана |

---

## UNIQUE ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | логин уникален |
| `client` | `phone_number` | BR-2.2 | телефон уникален |
| `client_address` | PK `(client_id, address_id)` | BR-2.5 | адрес нельзя привязать к клиенту дважды |
| `address` | `(street, house_number, apartment_office)` NULLS NOT DISTINCT | BR-3.3 | один физический адрес хранится одной строкой, иначе два ресторана смогут занять один адрес |
| `restaurant` | `address_id` | BR-3.3 | два ресторана не могут делить адрес |
| `product_category` | `product_category_name` | BR-5.7 | категория это справочник |
| `courier` | `phone_number` | BR-6.1 | телефон курьера |
| `courier_pay` | PK `(year, month, courier_id)` | BR-10.3 | одна запись на курьера за месяц |
| `order` | `(order_id, client_id)` | BR-9.2 | нужен для составного FK из `review` |
| `order_structure` | PK `(order_id, product_id)` | BR-7.16 | блюдо не повторяется в заказе |
| `payment` | `transaction_id` | BR-8.3 | идентификатор транзакции уникален |
| `payment` | `(order_id) WHERE status = 'успех'` | BR-8.1 | не больше одной успешной оплаты на заказ |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | один отзыв на объект в рамках заказа |

---

## FK ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client` | BR-2.4 | адрес клиента |
| `client_address` | `address_id` | `address` | BR-2.4 | адрес клиента |
| `restaurant` | `address_id` | `address` | BR-3.3 | у ресторана один адрес |
| `product` | `restaurant_id` | `restaurant` | BR-5.1 | блюдо принадлежит ресторану |
| `product` | `product_category_id` | `product_category` | BR-5.1 | блюдо принадлежит категории |
| `courier_pay` | `courier_id` | `courier` | BR-10.2 | выплата курьеру |
| `order` | `client_id` | `client` | BR-7.2 | заказ клиента |
| `order` | `restaurant_id` | `restaurant` | BR-7.2 | заказ в ресторане |
| `order` | `courier_id` | `courier` | BR-7.5 | доставляет курьер |
| `order` | `address_id` | `address` | BR-7.4 | адрес доставки |
| `order` | `(client_id, address_id)` | `client_address` | BR-7.4 | адрес именно этого клиента |
| `order_structure` | `order_id` | `order` | BR-7.14 | позиция заказа |
| `order_structure` | `product_id` | `product` | BR-7.14 | блюдо в позиции |
| `payment` | `order_id` | `order` | BR-8.1 | оплата заказа |
| `review` | `client_id` | `client` | BR-9.1 | отзыв клиента |
| `review` | `order_id` | `order` | BR-9.2 | отзыв по заказу |
| `review` | `(order_id, client_id)` | `order` | BR-9.2 | заказ этого клиента |

Удаление везде запрещено (RESTRICT), чтобы сохранялась история (BR-3.5). Исключение `client_address.client_id`: при удалении клиента удаляются только его привязки к адресам, сами адреса остаются.

---

## NOT NULL (только бизнес обязательные)

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `order` | `courier_id` | BR-1.3, BR-7.5 | все заказы доставляет курьер |
| `order` | `description` | BR-11.3 | NULL разрешён только там, где это сказано в BR |
| `courier` | `coefficient` | BR-6.5 | у нового курьера сразу 0.1 |
| `restaurant` | `company_details` | BR-4.1, BR-4.5 | реквизиты есть у каждого ресторана |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2 | частный дом |
| `product` | `photo_url` | BR-5.6 | фото необязательно |
| `review` | `photo_url` | BR-9.3 | фото необязательно |
| `courier` | `dismissal_date` | BR-6.3 | курьер работает |
| `order` | `delivery_timestamp` | BR-7.12 | заказ ещё не доставлен |
| `product` | `rating` | BR-9.7 | нет отзывов |
| `restaurant` | `rating` | BR-9.7 | нет отзывов |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| все | id | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 |
| `courier` | `coefficient` | `DEFAULT 0.1` | BR-6.5 |
| `order` | `order_timestamp` | `DEFAULT localtimestamp` | BR-7.1, BR-11.2 |
| `order` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | BR-1.4: комиссия всегда 10%, вручную её не ввести |
| `order` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED` | BR-7.10: сумма без комиссии плюс комиссия. STORED, чтобы работал CHECK `>= 1000` |

---

## Нормализация (3НФ)

```
Все атрибуты атомарны. В таблицах с составным ключом (client_address, order_structure,
courier_pay) неключевые атрибуты зависят от всего ключа. Транзитивных зависимостей нет:
адреса, категории и рестораны вынесены в свои таблицы.

Особые случаи:
order.commission и order.total_amount вычисляются из order_amount. Сделаны GENERATED,
поэтому их нельзя записать с ошибкой.
product.rating и restaurant.rating это агрегаты по отзывам. Хранятся для быстрого
чтения, пересчитываются триггером rating_change.
review.entity_id + entity_type это полиморфизм, 3НФ не нарушает (см. ловушку 4).
Таблица "order" названа в кавычках, как в erd.md (BR-13.1).
```
