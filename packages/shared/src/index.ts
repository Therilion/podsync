export enum RoomStatus {
  ACTIVE = 'active',
  CLOSED = 'closed',
}

export enum ParticipantRole {
  HOST = 'host',
  GUEST = 'guest',
}

export enum ParticipantStatus {
  CONNECTED = 'connected',
  DISCONNECTED = 'disconnected',
  LEFT = 'left',
}

export interface RoomSummary {
  id: string;
  code: string;
  status: RoomStatus;
  createdAt: string;
}

export interface ParticipantInfo {
  id: string;
  displayName: string;
  role: ParticipantRole;
  status: ParticipantStatus;
}
