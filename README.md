# GG Vegas Affiliate Reporting Pipeline

### From Raw Data to Slack: Automating Weekly Performance Insights

This project builds a direct bridge between our raw data and the marketing team.
Instead of requiring manual data pulls, this system extracts player activity, transforms it into clear KPIs, and pushes a weekly performance snapshot straight to Slack.

## The Goal & Impact
Affiliate marketing drives a significant portion of our player base. Previously, tracking performance required manual queries or checking disparate systems.

**This project solves that by:**
* **Centralizing Truth:** Creating a single, reliable source of truth for Affiliate vs. Organic traffic in Snowflake.
* **Automating Insights:** Delivering a "zero-click" weekly report to stakeholders via Slack.
* **Driving Action:** Empowering the marketing team to react faster to trends in Registrations, FTDs (First Time Deposits), and GGR (Gross Gaming Revenue).

---

## The Final Product

### 1. Automated Weekly Push (Slack)
Every Monday morning, the Push Metrics tool grabs the latest snapshot from Tableau and posts it to the `#notice-ggvegas-kpi` channel. This ensures the team starts the week with the data they need, right where they work.

<img width="693" height="666" alt="image" src="https://github.com/user-attachments/assets/c26f4cb5-7cc6-413c-b891-ad4139471fee" />

*Above: The automated message stakeholders receive every Monday.*

### 2. The Interactive Dashboard (Tableau)
The dashboard provides a deep dive into the 4 critical pillars of affiliate performance: **Registrations**, **Active Users (AU)**, **GGR vs. Theo Win**, and **Deposits**.

<img width="1024" height="569" alt="image" src="https://github.com/user-attachments/assets/cfcd5361-c2d1-4558-8f07-d6045e40be49" />

*Above: The full interactive view allowing drill-downs by date and affiliate type.*

---

## Technical Architecture

This pipeline follows a modern **ELT (Extract, Load, Transform)** workflow:

```mermaid
graph LR
    subgraph Snowflake Data Warehouse
        A["Raw Player Data<br/>(Transactions, Game Logs)"] --> B{SQL Transformation}
        B -->|Aggregates & Filters| C["Dynamic Table<br/>GGVEGAS_AFFILIATE_PUSH"]
    end
    
    C --> D[Tableau Dashboard]
    D --> E[Push Metrics Tool]
    E --> F["Slack Channel<br/>#affiliates"]
    
    style C fill:#0077b6,stroke:#333,stroke-width:2px,color:#fff
    style D fill:#e63946,stroke:#333,stroke-width:2px,color:#fff
    style F fill:#4a4e69,stroke:#333,stroke-width:2px,color:#fff
