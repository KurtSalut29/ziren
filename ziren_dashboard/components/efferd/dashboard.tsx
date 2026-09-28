import { ChannelBreakdownChart } from "@/components/efferd/channel-breakdown-chart";
import { ConversationVolumeChart } from "@/components/efferd/conversation-volume-chart";
import { CsatResponsesChart } from "@/components/efferd/csat-responses-chart";
import { FirstReplyTimeChart } from "@/components/efferd/first-reply-time-chart";
import { RecentConversations } from "@/components/efferd/recent-conversations";
import { DashboardStats } from "@/components/efferd/stats";
import { SupportActivity } from "@/components/efferd/support-activity";
import { TeamOnDuty } from "@/components/efferd/team-on-duty";

export function Dashboard() {
	return (
		<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
			<DashboardStats />
			<ConversationVolumeChart />
			<ChannelBreakdownChart />
			<CsatResponsesChart />
			<FirstReplyTimeChart />
			<TeamOnDuty />
			<RecentConversations />
			<SupportActivity />
		</div>
	);
}
