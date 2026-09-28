import { apiClient } from './client';

export interface NotificationItem {
  id: string;
  type: string;
  title: string;
  body: string | null;
  is_important: boolean;
  is_read: boolean;
  link: string | null;
  created_at: string;
}

export interface NotificationList {
  items: NotificationItem[];
  total: number;
  unread_count: number;
}

export const fetchNotifications = (token: string, unreadOnly = false, limit = 30) =>
  apiClient.get<NotificationList>(
    `/notifications/?unread_only=${unreadOnly}&limit=${Math.min(200, limit)}`,
    token,
  );

export const fetchUnreadCount = (token: string) =>
  apiClient.get<{ unread_count: number }>('/notifications/unread-count', token);

export const markNotificationRead = (id: string, token: string) =>
  apiClient.patch<NotificationItem>(`/notifications/${id}/read`, {}, token);

export const markAllNotificationsRead = (token: string) =>
  apiClient.patch<{ updated: number }>('/notifications/read-all', {}, token);
