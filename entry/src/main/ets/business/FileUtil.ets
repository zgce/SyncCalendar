import { fileIo } from '@kit.CoreFileKit'

export class FileUtil {
  static fileExists(filePath: string): boolean {
    try {
      const stat = fileIo.statSync(filePath);
      return stat.isDirectory() || stat.isFile();
    } catch (error) {
      console.error(`get file ${filePath} stat failed! errmsg: ${error}`)
      return false;
    }
  }
}

