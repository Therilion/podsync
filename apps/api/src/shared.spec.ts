import { RoomStatus } from '@podsync/shared';

describe('@podsync/shared resolution from api', () => {
  it('resolves RoomStatus.ACTIVE to "active"', () => {
    expect(RoomStatus.ACTIVE).toBe('active');
  });
});
