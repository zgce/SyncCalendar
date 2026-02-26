import { fileIo } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { ReadTextOptions, WriteOptions } from '@kit.CoreFileKit'

const DOMAIN = 0x0001;
const LOG_TAG = "FileUtilTag"
export class FileUtil {

  static fileExists(filePath: string): boolean {
    try {
      const stat = fileIo.statSync(filePath)
      return stat.isDirectory() || stat.isFile()
    } catch (error) {
      hilog.error(DOMAIN, LOG_TAG, `get file ${filePath} stat failed! errmsg: ${Error(error).message}`)
      return false;
    }
  }

  static writeTextFile(filePath: string, content: string) {
    try {
      const fd = fileIo.openSync(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      let options: WriteOptions = { encoding: 'utf-8' }
      try {
        fileIo.writeSync(fd.fd, content, options)
      } catch (err) {
        hilog.error(DOMAIN, LOG_TAG, `writeToFile(${filePath}) failed! ${Error(err).message}}`)
      } finally {
        fileIo.closeSync(fd)
      }
      hilog.info(DOMAIN, LOG_TAG, `writeToFile(${filePath}) length ${content.length} succeed.`)
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `writeToFile(${filePath}) failed! ${Error(err).message}`)
    }
  }

  static readTextFile(filePath: string): string {
    try {
      let options: ReadTextOptions = { encoding: 'utf-8' };
      let content = fileIo.readTextSync(filePath, options);
      return content;
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, `readTextFile(${filePath}) failed ${Error(err).message}}`)
      return '';
    }
  }
}

