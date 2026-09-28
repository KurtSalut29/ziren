import React, { useState } from "react";
import {
  Siren,
  Plus,
  Building2,
  History,
  Archive,
  HelpCircle,
  MapPin,
  Radio,
  ChevronRight,
  LogOut,
} from "lucide-react";

const navItems = [
  { icon: Plus, label: "New incident", key: "new" },
  { icon: Building2, label: "Agencies", key: "agencies" },
  { icon: Radio, label: "Live dispatch", key: "dispatch" },
  { icon: Archive, label: "Reports", key: "reports" },
  { icon: HelpCircle, label: "How it works", key: "help" },
];

const recentIncidents = [
  { title: "Structure fire, Brgy. Caraycaray", time: "2m ago", agency: "BFP" },
  { title: "Traffic collision, Naval–Caibiran Rd", time: "18m ago", agency: "PNP" },
  { title: "Flood advisory, Brgy. Sabang", time: "1h ago", agency: "MDRRMO" },
  { title: "Medical assist, Brgy. Libtong", time: "3h ago", agency: "BFP" },
];

export default function ZirenSidebarLayout() {
  const [active, setActive] = useState("new");

  return (
    <div className="flex h-[640px] w-full overflow-hidden rounded-3xl border border-neutral-200 bg-white font-[Nunito,sans-serif]">
      {/* Sidebar */}
      <aside className="flex w-64 shrink-0 flex-col border-r border-neutral-200 bg-[#FAFAFA]">
        {/* Logo */}
        <div className="flex items-center gap-2 px-5 pt-5 pb-4">
          <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-[#FC5A05]">
            <Siren size={18} className="text-white" />
          </div>
          <span className="text-[15px] font-bold tracking-tight text-neutral-900">
            Ziren
          </span>
        </div>

        {/* Primary nav */}
        <nav className="flex flex-col gap-1 px-3">
          {navItems.map(({ icon: Icon, label, key }) => {
            const isActive = active === key;
            return (
              <button
                key={key}
                onClick={() => setActive(key)}
                className={`flex items-center gap-3 rounded-2xl px-3 py-2.5 text-left text-[13px] font-semibold transition-colors ${
                  isActive
                    ? "bg-[#FFF0E6] text-[#C94600]"
                    : "text-neutral-600 hover:bg-neutral-100"
                }`}
              >
                <Icon size={17} strokeWidth={2} />
                {label}
              </button>
            );
          })}
        </nav>

        {/* Recent incidents */}
        <div className="mt-5 flex-1 overflow-y-auto px-3">
          <p className="px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-neutral-400">
            Recent incidents
          </p>
          <div className="flex flex-col gap-1">
            {recentIncidents.map((item, i) => (
              <button
                key={i}
                className="flex flex-col gap-0.5 rounded-2xl px-3 py-2 text-left hover:bg-neutral-100"
              >
                <span className="truncate text-[12.5px] font-semibold text-neutral-800">
                  {item.title}
                </span>
                <span className="text-[11px] text-neutral-400">
                  {item.agency} · {item.time}
                </span>
              </button>
            ))}
          </div>
        </div>

        {/* User footer */}
        <div className="flex items-center gap-2.5 border-t border-neutral-200 px-4 py-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[#FC5A05] text-[12px] font-bold text-white">
            KB
          </div>
          <div className="flex-1 overflow-hidden">
            <p className="truncate text-[13px] font-bold text-neutral-900">
              Kurt B.
            </p>
            <p className="truncate text-[11px] text-neutral-400">
              Agency admin
            </p>
          </div>
          <LogOut size={15} className="shrink-0 text-neutral-400" />
        </div>
      </aside>

      {/* Main content placeholder */}
      <main className="flex flex-1 flex-col bg-white">
        <div className="flex items-center justify-between border-b border-neutral-200 px-6 py-4">
          <div className="flex items-center gap-2">
            <MapPin size={16} className="text-[#FC5A05]" />
            <span className="text-[14px] font-bold text-neutral-800">
              Biliran Island · Dispatch view
            </span>
          </div>
          <button className="flex items-center gap-1 rounded-full bg-[#FC5A05] px-4 py-1.5 text-[12.5px] font-bold text-white">
            New incident
            <ChevronRight size={14} />
          </button>
        </div>
        <div className="flex flex-1 items-center justify-center text-[13px] text-neutral-300">
          Map / incident feed goes here
        </div>
      </main>
    </div>
  );
}
