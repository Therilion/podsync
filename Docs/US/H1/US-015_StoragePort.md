# US-015 — Interfaz de Abstracción de Almacenamiento (StoragePort)

> **Referencia completa:** Ver [00_README.md](00_README.md) para convenciones, política de versiones, diagrama de dependencias y ruta crítica.
> **Metodología:** Test Driven Development (Red → Green → Refactor)


> **Como** desarrollador,
> **quiero** tener una interfaz de abstracción para el almacenamiento de objetos (S3),
> **para** poder cambiar de SeaweedFS a otro proveedor en el futuro sin modificar la lógica de negocio.

**Referencia TDD:** §4.1.4 (StoragePort), §6.2.3 (Gestión de Chunks en S3)
**Prioridad:** P1-High
**Estimación total:** L (1–2 días)
**Dependencias:** US-002

### Criterios de Aceptación

1. Existe una interfaz `StoragePort` con métodos: `upload`, `download`, `getPresignedUrl`, `delete`, `deletePrefix`.
2. Existe una implementación `SeaweedFSStorageAdapter` que implementa `StoragePort` usando el SDK de AWS S3 contra SeaweedFS.
3. La implementación es inyectable via NestJS DI, registrada como provider con token `STORAGE_PORT`.
4. Upload y download de un archivo de prueba funcionan contra SeaweedFS en Docker Compose.
5. La implementación genera presigned URLs válidas con expiración configurable.

### Tareas

#### TASK-026: Implementar StoragePort interface y SeaweedFS adapter

| Campo | Valor |
|-------|-------|
| **ID** | TASK-026 |
| **Tamaño** | L |
| **Prioridad** | P1-High |
| **Dependencias** | TASK-006 |

**Especificación de implementación:**

1. Instalar AWS SDK v3 (compatible con SeaweedFS S3 API):
   ```bash
   pnpm add @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
   ```

2. Crear interfaz y adapter:
   ```
   apps/api/src/storage/
   ├── storage.module.ts
   ├── storage.port.ts           # Interfaz
   ├── seaweedfs.adapter.ts      # Implementación
   └── seaweedfs.adapter.spec.ts # Tests
   ```

3. Interfaz `StoragePort` (según §6.2.3 del TDD):
   ```typescript
   export const STORAGE_PORT = Symbol('STORAGE_PORT');

   export interface StoragePort {
     upload(key: string, data: Buffer, contentType: string): Promise<void>;
     download(key: string): Promise<Buffer>;
     getPresignedUrl(key: string, expiresIn: number): Promise<string>;
     delete(key: string): Promise<void>;
     deletePrefix(prefix: string): Promise<void>;
   }
   ```

4. Implementar `SeaweedFSStorageAdapter`:
   ```typescript
   @Injectable()
   export class SeaweedFSStorageAdapter implements StoragePort {
     private client: S3Client;
     private bucket: string;

     constructor(private configService: ConfigService) {
       this.client = new S3Client({
         endpoint: this.configService.get('S3_ENDPOINT'),
         region: 'us-east-1', // SeaweedFS ignora region
         credentials: {
           accessKeyId: this.configService.get('S3_ACCESS_KEY'),
           secretAccessKey: this.configService.get('S3_SECRET_KEY'),
         },
         forcePathStyle: true, // Necesario para SeaweedFS
       });
       this.bucket = this.configService.get('S3_BUCKET');
     }

     async upload(key: string, data: Buffer, contentType: string): Promise<void> {
       await this.client.send(new PutObjectCommand({
         Bucket: this.bucket, Key: key, Body: data, ContentType: contentType,
       }));
     }

     async download(key: string): Promise<Buffer> {
       const response = await this.client.send(new GetObjectCommand({
         Bucket: this.bucket, Key: key,
       }));
       return Buffer.from(await response.Body.transformToByteArray());
     }

     async getPresignedUrl(key: string, expiresIn: number): Promise<string> {
       return getSignedUrl(
         this.client,
         new GetObjectCommand({ Bucket: this.bucket, Key: key }),
         { expiresIn },
       );
     }

     async delete(key: string): Promise<void> {
       await this.client.send(new DeleteObjectCommand({
         Bucket: this.bucket, Key: key,
       }));
     }

     async deletePrefix(prefix: string): Promise<void> {
       const listResponse = await this.client.send(new ListObjectsV2Command({
         Bucket: this.bucket, Prefix: prefix,
       }));
       if (!listResponse.Contents?.length) return;
       await this.client.send(new DeleteObjectsCommand({
         Bucket: this.bucket,
         Delete: { Objects: listResponse.Contents.map(obj => ({ Key: obj.Key })) },
       }));
     }
   }
   ```

5. `StorageModule`:
   ```typescript
   @Global()
   @Module({
     providers: [
       {
         provide: STORAGE_PORT,
         useClass: SeaweedFSStorageAdapter,
       },
     ],
     exports: [STORAGE_PORT],
   })
   export class StorageModule {}
   ```

**Tests TDD (integration contra SeaweedFS en Docker):**

```typescript
describe('SeaweedFSStorageAdapter', () => {
  it('should upload and download a file', async () => {
    const content = Buffer.from('test audio data');
    await adapter.upload('test/file.webm', content, 'audio/webm');

    const downloaded = await adapter.download('test/file.webm');
    expect(downloaded.toString()).toBe('test audio data');
  });

  it('should generate a presigned URL', async () => {
    await adapter.upload('test/presigned.webm', Buffer.from('data'), 'audio/webm');
    const url = await adapter.getPresignedUrl('test/presigned.webm', 3600);
    expect(url).toContain('test/presigned.webm');
  });

  it('should delete a file', async () => {
    await adapter.upload('test/delete-me.webm', Buffer.from('data'), 'audio/webm');
    await adapter.delete('test/delete-me.webm');
    await expect(adapter.download('test/delete-me.webm')).rejects.toThrow();
  });

  it('should delete all files with a prefix', async () => {
    await adapter.upload('test/prefix/a.webm', Buffer.from('a'), 'audio/webm');
    await adapter.upload('test/prefix/b.webm', Buffer.from('b'), 'audio/webm');
    await adapter.deletePrefix('test/prefix/');
    await expect(adapter.download('test/prefix/a.webm')).rejects.toThrow();
    await expect(adapter.download('test/prefix/b.webm')).rejects.toThrow();
  });
});
```
