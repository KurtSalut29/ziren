'use client';

/**
 * One assist inbox for the whole console. The layout owns the poll (it has to:
 * the alert must reach the admin on every page), and publishes the result here
 * so the Assist Requests page, the sidebar badge and the incident detail view
 * all read the same list instead of each polling for their own copy.
 */

import { createContext, useContext } from 'react';
import type { AssistInbox } from '@/lib/hooks/useAssistInbox';

const AssistInboxContext = createContext<AssistInbox | null>(null);

export const AssistInboxProvider = AssistInboxContext.Provider;

/** Null outside the dashboard layout. */
export function useAssistInboxContext(): AssistInbox | null {
  return useContext(AssistInboxContext);
}
