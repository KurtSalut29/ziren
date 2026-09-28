import { Kbd, KbdGroup } from "@/components/efferd/ui/kbd";
import { SidebarTrigger } from "@/components/efferd/ui/sidebar";
import {
	Tooltip,
	TooltipContent,
	TooltipTrigger,
} from "@/components/efferd/ui/tooltip";

export function CustomSidebarTrigger() {
	return (
		<Tooltip delayDuration={1000}>
			<TooltipTrigger asChild>
				<SidebarTrigger />
			</TooltipTrigger>
			<TooltipContent className="px-2 py-1" side="right">
				Toggle Sidebar{" "}
				<KbdGroup>
					<Kbd>⌘</Kbd>
					<Kbd>b</Kbd>
				</KbdGroup>
			</TooltipContent>
		</Tooltip>
	);
}
