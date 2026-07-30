/**
 * Thumbnail URLs are scoped by account because object IDs may overlap between
 * different Cloudreve sites or users.
 */
export class FileThumbSourceCache {
  private static data: Map<string, string> = new Map<string, string>()

  static get(key: string): string {
    return FileThumbSourceCache.data.get(key) ?? ''
  }

  static set(key: string, source: string): void {
    FileThumbSourceCache.data.set(key, source)
  }

  static snapshot(scope: string): Map<string, string> {
    const result = new Map<string, string>()
    FileThumbSourceCache.data.forEach((source: string, key: string) => {
      if (key.startsWith(scope)) {
        result.set(key.substring(scope.length), source)
      }
    })
    return result
  }
}
