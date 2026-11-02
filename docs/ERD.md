# ERD MVP SeiCycle

Firestore bersifat document database, sehingga diagram berikut menunjukkan relasi logis melalui UID dan `moduleType`, bukan foreign key database.

```mermaid
erDiagram
    USERS ||--o{ LOGBOOKS : creates
    USERS ||--o{ INVENTORY : creates
    USERS ||--o{ SCHEDULES : creates
    USERS ||--o{ FINANCE_TRANSACTIONS : creates
    USERS ||--o{ NOTIFICATIONS : receives
    FARM_MODULES ||--o{ LOGBOOKS : categorizes
    FARM_MODULES ||--o{ SCHEDULES : categorizes
    FARM_MODULES ||--o{ RECOMMENDATIONS : targets

    USERS {
        string id PK
        string uid
        string name
        string email
        string photoUrl
        string role
        boolean isActive
        timestamp createdAt
        timestamp updatedAt
    }

    FARM_MODULES {
        string id PK
        string name
        string type
        string description
        string icon
        string color
        boolean isActive
        timestamp updatedAt
    }

    LOGBOOKS {
        string id PK
        string moduleType
        string createdBy
        string updatedBy
        string title
        timestamp activityDate
        number quantity
        string unit
        string status
        string notes
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    INVENTORY {
        string id PK
        string createdBy
        string updatedBy
        string name
        string category
        string unit
        number currentStock
        number minStock
        boolean isLowStock
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    SCHEDULES {
        string id PK
        string moduleType
        string createdBy
        string updatedBy
        string title
        string type
        timestamp date
        string status
        string notes
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    NOTIFICATIONS {
        string id PK
        string userId
        string title
        string body
        string type
        string status
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    EDUCATION_CONTENTS {
        string id PK
        string title
        string type
        string content
        string externalUrl
        boolean isPublished
        string createdBy
        string updatedBy
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    FINANCE_TRANSACTIONS {
        string id PK
        string createdBy
        string updatedBy
        string type
        string category
        number amount
        timestamp date
        string notes
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    REPORT_METADATA {
        string id PK
        string title
        string type
        timestamp periodStart
        timestamp periodEnd
        string status
        string createdBy
        string updatedBy
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }

    RECOMMENDATIONS {
        string id PK
        string moduleType
        string title
        string description
        string priority
        string status
        string source
        string createdBy
        string updatedBy
        boolean isDeleted
        timestamp createdAt
        timestamp updatedAt
    }
```

AI otomatis, laporan file besar, Storage upload, Cloud Functions, dan backend API berada di luar scope MVP ini.
