/**
 * Types for the console's demos — the mascot walking a dispatcher through a
 * page, part by part. Content lives in demo-content.ts.
 */

/** Poses cut from branding/Demo_Mascots.png into public/demo/. */
export type DemoPose =
  | 'point_left'
  | 'point_right'
  | 'point_up'
  | 'point_down'
  | 'point_you'
  | 'thinking'
  | 'excited'
  | 'confused'
  | 'wink'
  | 'ok'
  | 'front'
  | 'running'
  | 'jumping'
  | 'sitting';

export interface DemoStep {
  /**
   * The `data-demo` value of the part being explained. Left out — or not on
   * the page right now (an empty table, a closed panel) — the mascot says the
   * line from the middle of the screen instead of pointing at nothing.
   */
  target?: string;
  text: string;
  /** Leave unset to point at the target from wherever the bubble lands. */
  pose?: DemoPose;
  /**
   * The step is inside the script's `dialog`: the tour opens it before the
   * step (and closes it again on the first step that is not), and sits above
   * it while the step is shown.
   */
  dialog?: boolean;
}

export interface DemoScript {
  id: string;
  title: string;
  summary: string;
  /** The page the demo runs on; opening the demo goes there first. */
  href: string;
  /** Who sees it: both admin roles unless narrowed. */
  roles?: 'agency' | 'provincial';
  /**
   * A dialog the page opens for the demo (useDemoDialog), for the steps marked
   * `dialog`. When the page has nothing to show in it, those steps are said
   * from the middle of the screen.
   */
  dialog?: string;
  steps: DemoStep[];
}
