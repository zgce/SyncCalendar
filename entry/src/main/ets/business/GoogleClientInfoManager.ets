import { fileIo } from '@kit.CoreFileKit'
import { StrUtil } from '@pura/harmony-utils'
import type { ReadTextOptions, WriteOptions } from '@kit.CoreFileKit'
import { FileUtil } from './FileUtil'

/**
 * 代理信息结构
 */
export interface ProxyInfo {
  proxyIp: string;
  proxyPort: number;
  proxyUser: string;
  proxyPwd: string;
}

/**
 * Google客户端配置信息
 */
export interface GoogleClientInfo {
  name: string;
  clientId: string;
  clientSecret: string;
  clientRefreshToken: string;
  proxy: ProxyInfo
}

/**
 * Google客户端信息管理器
 */
export class GoogleClientInfoManager {
  private clientInfos: GoogleClientInfo[] = [];
  private readonly STORAGE_FILE_PATH: string = 'google_client_infos.json';
  public static GLOBAL_NAME: string = 'GoogleClientManager';

  /**
   * 添加一个GoogleClientInfo
   * @param clientInfo
   */
  addClientInfo(clientInfo: GoogleClientInfo) {
    this.clientInfos.push(clientInfo);
    console.info(`add client info ${clientInfo.name} length ${this.clientInfos.length}`)
  }

  /**
   * 删除一个GoogleClientInfo
   * @param clientId
   */
  removeClientInfo(clientId: string) {
    this.clientInfos = this.clientInfos.filter(info => info.clientId !== clientId);
  }

  /**
   * 获取所有GoogleClientInfo
   */
  getClientInfos(): GoogleClientInfo[] {
    return this.clientInfos;
  }

  /**
   * 获取一个GoogleClientInfo
   * @param clientId
   */
  getClientInfo(clientId: string): GoogleClientInfo | undefined {
    return this.clientInfos.find(info => info.clientId === clientId);
  }

  /**
   * 清空所有GoogleClientInfo
   */
  clearClientInfos() {
    this.clientInfos = [];
  }

  loadFromFile(filesDir: string) {
    try {
      const filePath = filesDir + '/' + this.STORAGE_FILE_PATH;
      if (FileUtil.fileExists(filePath)) {
        let options: ReadTextOptions = { encoding: 'utf-8' };
        const readData = fileIo.readTextSync(filePath, options);
        if (StrUtil.isNotBlank(readData)) {
          const parseData = JSON.parse(readData) as Array<GoogleClientInfo>;
          if (Array.isArray(parseData)) {
            this.clientInfos = parseData;
            console.log(`loadFromFile(${filePath}) length ${parseData.length} succeed.`)
          } else {
            console.error(`parse text data ${readData} to Array<GoogleClientInfo> failed!`);
          }
        }
      }
    } catch (error) {
      console.error(`file to load data from file. errmsg: ${error}`);
      this.clientInfos = [];
    }
  }

  saveToFile(filesDir: string) {
    try {
      const filePath = filesDir + '/' + this.STORAGE_FILE_PATH;
      const jsonData = JSON.stringify(this.clientInfos);
      const fd = fileIo.openSync(filePath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      let options: WriteOptions = { encoding: 'utf-8' };
      fileIo.writeSync(fd.fd, jsonData, options);
      fileIo.closeSync(fd);
      console.log(`saveToFile(${filePath}) length ${this.clientInfos.length} succeed.`);
    } catch (e) {
      console.error('saveToFile() failed', e);
    }
  }
}
