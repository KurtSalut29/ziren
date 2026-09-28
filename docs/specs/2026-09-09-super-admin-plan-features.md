# Ziren Plan Features — Super Admin

Transcribed from "Ziren Plan Features – Super Admin.pdf" (provided 2026-09-09). This is the
source spec for `docs/superpowers/plans/2026-09-09-super-admin-features.md`.

## 1. Role Definition and Responsibility

The current Ziren dashboard gives Super Admin and Agency Admin overlapping features. To fix
role-based access control and usability, the two roles get clearly differentiated
responsibilities.

**Super Admin** = system-wide administrator and governance authority: manage the platform,
monitor all agencies, manage user accounts, oversee system activity, analyze province-wide
information.

**Agency Admin** = agency-level operations and emergency response management: receiving
incidents, coordinating responders, managing incidents assigned to their agency.

Super Admin also creates and manages Agency Station accounts — stations no longer request
account creation from the Super Admin.

**Super Admin primary responsibilities**: manage the entire Ziren platform; create/manage
agency station accounts; manage residents, agency administrators, and responders; verify
registered accounts; monitor incidents across all agencies; monitor system-wide geographic
information; analyze incident and system trends; monitor agency performance; manage
system-wide configurations and policies; monitor AI/NLP-related system performance; review
administrative activity through audit logs; publish system-wide announcements; manage
personal and accessibility preferences.

**The Super Admin will not directly receive, dispatch, or operationally process emergency
incidents.**

## 2. Dashboard

Province-wide overview of the Ziren platform. High-level administrative/analytical
information, not active dispatch operations. Answers: *"What is the current overall state of
the Ziren system?"* Not an operational dispatch dashboard.

## 3. Incident Monitoring

Rename **Incidents** → **Incident Monitoring**. System-wide visibility over incident reports
submitted to BFP, PNP, MDRRMO — monitoring only, not receiving/dispatching.

Each incident may display: Incident ID, incident type, location, reporting resident, assigned
agency, current status, date/time reported, date/time resolved, severity classification,
assigned responders, resolution information.

Statuses monitored: Pending, Under Verification, Accepted, In Progress, Resolved, Cancelled.

Super Admin should **not**: receive emergency incidents directly, assign responders, dispatch
responders, manage operational routes, directly handle agency response activities.

Purpose — Agency Admin: *"How do we respond to this incident?"* Super Admin: *"What is
happening across the entire Ziren system?"*

## 4. Verification

Centralized verification of registered accounts: resident registrations, agency station
registrations, agency admin accounts, responder accounts.

Actions: review submitted information, approve accounts, reject accounts, request additional
information, view verification history.

## 5. Accounts

Centralized account management for all registered accounts.

**Residents** — organized Municipality → Barangay → Residents. Super Admin can: view resident
info, search residents, filter by municipality, filter by barangay, suspend/deactivate/
reactivate accounts.

**Agency Administrators** — organized by agency and station, e.g. BFP → Naval Station →
Agency Admin.

**Responders** — organized by agency and station. Super Admin can: view responder info, assign
responders to stations when applicable, suspend/deactivate/reactivate accounts, review account
activity.

Super Admin has centralized authority over all accounts in the system.

## 6. Agency Management

New dedicated module — Super Admin manages agency stations: BFP/PNP/MDRRMO stations, agency
admin accounts, station information, station status, station personnel.

**Agency Station Management** actions: create an agency station account, edit station
information, assign an Agency Admin, replace an Agency Admin, activate a station, deactivate a
station, view station personnel, view station activity.

## 7. Incident Map

Different from the Agency Admin's operational map — a system-wide geographic monitoring map,
not a dispatch map. Two views:

**A. Ziren Network Map** — registered residents, agency stations, responders. Filterable by
municipality, barangay, account type, agency, station.

**B. Incident History Map** — resolved, completed, historical incidents. No operational route
from incident location to responding station is shown.

Purpose — Super Admin map: *"Where are Ziren's users, agencies, responders, and historical
incidents located?"* Agency Admin map: *"Where is the incident and how should our agency
respond?"*

## 8. Geographic Overview

Replaces the removed **Coverage Areas** feature. Province-wide geographic information: select
Municipality → Barangay and view registered residents, registered responders, agency stations,
nearby agencies, incident count, incident types, resolved incidents, active incidents,
historical incident activity.

Purpose: identify municipalities with low Ziren adoption, barangays with few registered users,
areas with limited agency representation, areas with high incident activity, areas that may
need additional responder coverage.

## 9. System Analytics

New module for long-term trend analysis (Dashboard = current state; Analytics = trends).

**Incident Analytics**: incidents per day/month/year; by municipality; by barangay; by agency;
by incident type; resolved vs. unresolved; average resolution time; incident frequency trends.

**User Analytics**: resident registration trends; responder growth; agency station growth;
user distribution by municipality; user distribution by barangay.

**Agency Analytics**: incidents handled per agency; resolution rates; average response time;
average resolution time; completed vs. cancelled incidents.

## 10. Audit Logs

Records important administrative activities: who performed an action, what action, which
account/record was affected, date and time, previous value (when applicable), new value (when
applicable).

Example rows: Agency Admin suspended Responder #104; Super Admin created station BFP Naval;
Agency Admin updated incident INC-1024.

Purpose: accountability, transparency, security monitoring, administrative traceability.
Answers: *"Who changed this, when was it changed, and what was changed?"*

## 11. System Governance

Replaces the standalone **Rubric Config** feature.

- **Incident Configuration** — incident categories, incident statuses, classification settings.
- **Severity Configuration** — severity rule versions, agency-specific severity policies,
  system thresholds.
- **Account Policies** — verification requirements, account status policies, suspension
  policies.
- **Notification Policies** — system alerts, administrative notifications, incident-related
  notifications.
- **Configuration History** — every critical configuration change recorded (e.g. "BFP Severity
  Rules — Previous Version v1.2, New Version v1.3, Modified by Super Admin, Date...").

## 12. AI and Classification Monitoring

Under System Governance. Super Admin **cannot** directly modify the trained model from the
dashboard — monitoring only: current AI model version, model status, classification
statistics, AI-assisted classification count, confidence distribution, human
verification/correction records, model evaluation metrics. Example: "AI Prediction: Fire,
Human Verification: Fire, Result: Correct."

## 13. System Status

Health of important Ziren services: Authentication, Database, Incident service, Notification
service, Map service, AI/NLP service, File storage, Realtime services. Example:
Authentication — Operational, Database — Operational, etc.

## 14. Announcements

Super Admin publishes system-wide announcements: system maintenance, emergency notices,
service interruptions, new system features, administrative announcements, important reminders.
Targetable to: all users, Agency Admins, Responders, Residents, specific agencies.

## 15. Notifications

The notification bell becomes a functional notification center. Possible notifications: new
account registrations, verification requests, new agency station creation, account
suspension/deactivation, security alerts, system configuration changes, system announcements.
Support: read/unread status, important notifications, notification history, unread count.
Badge on the bell when unread notifications exist.

## 16. Reports and Data Export

Generate: monthly incident reports, agency performance reports, municipality incident reports,
barangay incident reports, resident registration reports, responder reports, incident
resolution reports. Export formats: PDF, CSV, Excel.

## 17. Settings

Redesign around personalization, accessibility, security, user preferences.

- **Profile** — edit personal info, add profile info, change photo, update contact info,
  change password.
- **Appearance** — Light/Dark/System. Light Mode improvement: replace pure white with a soft
  off-white/light-neutral theme (soft off-white background, slightly darker card surfaces, dark
  gray text instead of pure black, subtle borders, Ziren orange as primary accent) — keeps
  Light Mode's identity while being easier to look at for long periods.
- **Accessibility** — font size, interface scaling, text spacing, high-contrast mode, reduced
  motion, larger controls, keyboard navigation support.
- **Notification Preferences** — configure which notifications a user receives.
- **Security** — change password, two-factor authentication (if implemented), active sessions,
  login history, security alerts.
- **Language** — preferred interface language, if implemented.

## 18. Global Search

The top search bar becomes a true Global Search (or is removed if not implemented properly).
Should search residents, responders, agency admins, agency stations, incidents, municipalities,
barangays. E.g. "INC-2026-00125" finds that incident; "BFP Naval" finds the station and related
records; "Naval" returns relevant users/stations/incidents/geographic records.

Global Search = whole system. Module Search = only the current module. Global Search should
only remain if properly implemented.

## 19. Sidebar and Branding

Increase the Ziren logo size in the sidebar — current logo too small for sufficient visual
identity. Sidebar should also provide appropriate spacing, clear navigation hierarchy,
consistent icon sizing, proper active-state indication, without the logo consuming too much
sidebar space.

## 20. Sign-Out Confirmation

Sign Out requires confirmation before terminating the session:

> **Sign Out?**
> Are you sure you want to sign out of your Ziren account?
> [Cancel] [Sign Out]

## Recommended Super Admin Navigation

- **Overview** — Dashboard
- **Monitoring** — Incident Monitoring, Incident Map, System Analytics, Geographic Overview
- **Management** — Accounts, Agencies, Verification
- **Governance** — System Governance, AI & Classification, Audit Logs, System Status
- **Communication** — Notifications, Announcements, Reports & Export
- **Personal** — Settings

## Final Super Admin Role Definition

Four major responsibilities: **Manage** (users, agency stations, agency admins, responders,
system configurations) → **Monitor** (incidents, agencies, users, geographic distribution,
system health, administrative activities) → **Analyze** (incident trends, agency performance,
geographic patterns, user growth, AI classification performance) → **Govern** (system
policies, severity configurations, account policies, system announcements, security/audit
records).

| Role | Primary Responsibility | Loop |
|---|---|---|
| Super Admin | System-wide management, governance, monitoring, and analysis | Manage → Monitor → Analyze → Govern |
| Agency Admin | Agency-level emergency operations and incident coordination | Receive → Verify → Dispatch → Coordinate → Resolve |
| Responder | Field response and incident status updates | Respond → Update → Complete |
| Resident | Emergency incident reporting and incident tracking | Report → Track → Receive Updates |

The Super Admin has system-wide visibility **without becoming an operational dispatcher** —
this prevents duplication between the two admin roles and gives each role a clear, meaningful
purpose.
