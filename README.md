# SyncCalendar
  这是一个基于HarmonyOS NEXT平台开发的一个日历数据同步应用工具，它能将您的Google日历数据同步到手机上华为日历中

## 介绍
  HarmonyOS NEXT手机上的日历数据一直无法与电脑端同步，就算用上了HarmonyOS NEXT日历的CalDAV同步能力也只是只读，而现在大多数邮件
  厂商（包含Outlook）客户端都还未开启支持CalDAV的能力，而多数邮件客户端却都支持Google日历，所以有了这个项目的念头。

## 使用方法

1. 点击加号按钮增加一个Google日历配置
  ![刚进入软件](/doc/index_first.png)

2. 由于登录Google需要梯子(HTTP/HTTPS代理)，所以在配置的开头就有Proxy设置提示，若无须梯子，请直接开始配置
   ![刚开始配置](/doc/config_first.png)
   
    注意: 若代理服务器需要用户名和密码（HTTPS代理）则必须填写Client ID和Client Secret以及Refresh Token
因为鸿蒙系统的WebView的代理不支持设置用户名和密码

3. 若代理服务器的配置有用户名和密码，点击配开始配置按钮后，需要手工输入Client ID和Client Secret以及Refresh Token
  ![开始配置](/doc/config_client_up.png)

  若输入的代理服务无用户名和密码，或是就没有代理服务器，则点击开始配置按钮后，在下面的WebView里登入Google并确认授权
  ![开始配置](/doc/config_client_no.png)
   
4. 在配置完成后，会根据您的日历名称在手机日历中创建一个日历，用于存放同步的数据
  ![配置完成](/doc/calendar_custom.png)
