<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo/ipa-loom-lockup-on-dark.svg">
    <img src="docs/assets/logo/ipa-loom-lockup-primary.svg" alt="IPA Loom" width="640">
  </picture>
</p>

<h1 align="center">IPA Loom</h1>

<p align="center">
  <b>從 App Store 連結到驗證完成的 IPA，一套本機流程。</b>
</p>

<p align="center">
  <a href="README.md">English</a> · 繁體中文
</p>

---

## 這是什麼

IPA Loom 在 Apple Silicon Mac 上整合 IPA 下載、解密、驗證與清理。提供 App Store 連結、數字 App ID 或本機 IPA，同一個入口會引導首次設定和後續執行。不需要越獄裝置。

它使用 [ipatool](https://github.com/majd/ipatool) 處理 Apple 登入與個人化下載，使用 [UnfairPlay](https://github.com/DrWhax/unfairplay) 還原解密所需的本機註冊模型（enrollment model）並解密。Loom 負責本機憑證儲存、輸出命名、驗證、復原與清理，並未自行實作 FairPlay 解密演算法。

**預覽版：**工具建置及已設定環境的本機流程已通過測試。從首次 Apple 登入、模型初始化到解密的完整流程，仍待在未安裝 IPA Loom 的 Mac 上獨立驗證；目前不保證所有 App 或 macOS 版本都能使用。

## 操作畫面

<p align="center">
  <img src="docs/assets/screens/ipa-loom-help.png" alt="實際指令說明：設定、環境檢查、復原、建置檢查、清理、登入、輸出命名與舊式金鑰移除" width="900">
</p>

實際的英文 `./ipa-loom.command --help` 輸出，重新排版以方便閱讀；擷取時沒有執行初始化或存取 Apple 帳號，命令列介面及專案文件皆使用英文。

<p align="center">
  <img src="docs/assets/screens/ipa-loom-workflow.png" alt="合成流程示意：登入狀態檢查、下載、解密、明文驗證及虛構的 Example App IPA；不是實際解密結果" width="900">
</p>

**合成示意，不是實際執行紀錄。**展示登入狀態檢查、下載、解密、驗證與範例輸出；未使用帳號、私人模型或真實 IPA，也不代表完整首次設定已驗證成功。

## 開始使用

下載並解壓縮原始碼，開啟資料夾，雙擊 `ipa-loom.command`；也可以在該資料夾開啟終端機：

```sh
./ipa-loom.command
```

需要 Apple Silicon Mac、設定／下載時的網路連線，以及有權取得該 App 的 Apple 帳號。首次模型初始化另需從 Mac App Store 安裝並開啟一個 iPhone／iPad App，以及相符的 IPA。若缺少 Apple Command Line Tools，程式會取得你的同意後開啟 Apple 安裝程式。

精靈會建置經驗證的固定版本工具，引導 Apple 登入、App 比對、模型還原與驗證。Apple 密碼、雙重驗證碼、鑰匙圈授權及首次 macOS 管理員密碼都在本機處理；成功設定後，自動產生的解鎖金鑰才會存入本機鑰匙圈。需求與提示詳見[首次設定](docs/SETUP.md)。

## 日常使用

再次執行同一指令，依提示輸入目標。也可以直接處理既有 IPA：

```sh
./ipa-loom.command "/path/to/Example.ipa" --suffix my-tag
```

提供商店連結或 App ID 時，程式會先檢查登入並下載，再進行解密；本機 IPA 會跳過前兩步。後續執行沿用已設定的模型與鑰匙圈項目，但 Apple 重新驗證或鑰匙圈存取仍可能需要操作。只提供商店連結不會免除初始化與帳號條件。

輸出命名為 `StoreName_Version_loom.ipa`。商店名稱取自 IPA 中繼資料；缺少時依序使用 App 名稱等欄位。`--suffix` 只改變檔名標記，不是程式碼簽署。終端機會顯示輸出位置。

## 成功代表什麼

程式只有在以下檢查全部通過後才會回報成功：完整明文驗證報告、相符的輸出雜湊、有效的 ZIP 內容、與輸入一致的 App 身分及版本，以及不含 `SC_Info` 授權檔案。僅下載成功或結束碼為零並不足夠。

輸出**不會重新簽署**。驗證不代表 Apple 簽章可信、可安裝或 App 行為正常。僅使用你有權檢查的帳號、裝置與 App；請勿重新散布 App 套件或憑證。

## 你的資料

工具、加密帳號狀態、私人模型、快取、輸出與紀錄，都放在原始碼資料夾外的 `~/Library/Application Support/IPA Loom/`。鑰匙圈儲存獨立且不同步的解鎖金鑰。ipatool 的加密狀態包含 Apple 密碼與權杖，這個資料目錄必須保持私密。

測試套件在原始碼儲存庫之外私人維護，不隨原始碼公開。原始碼不附帶帳號、模型、真實 IPA 或私人測試紀錄；分享診斷資訊前，請閱讀[安全與資料處理](SECURITY.md)。

## 復原與清理

初始化會先在暫存目錄準備，驗證通過後才啟用；一般失敗會回復本次變更；若無法確認子程序已停止，或檔案擁有者修復失敗，則保留暫存資料供檢查。初始化中斷後可執行 `./ipa-loom.command --recover`；使用 `--doctor` 檢查本機準備狀態。

`--clean-runs` 預覽移除執行輸出與診斷資料，保留設定與摘要；`--reset` 預覽移除私人執行環境及其鑰匙圈項目。加入 `--apply` 才執行清理，請先保存需要的輸出。Apple 開發工具、已安裝 App、商店登入及外部備份不會被移除。詳見[操作說明](docs/OPERATIONS.md)。

## 文件

- [功能（英文）](docs/FEATURES.md) · [初始化與提示](docs/SETUP.md)
- [復原與清理](docs/OPERATIONS.md) · [安全](SECURITY.md)
- [上游元件與授權](docs/UPSTREAM.md) · [更新測試](docs/UPDATES.md)
- [貢獻與來源檢查](CONTRIBUTING.md) · [發版檢查](docs/RELEASING.md)

IPA Loom 提供上游新版偵測與獨立建置測試，不會自動替換已安裝工具。新版須通過相容性檢查，以及維護者使用授權帳號與 App 的實際流程測試，才會納入後續版本。尚待完成的驗證請見[發版準備狀態](docs/RELEASE-READINESS.md)。

## 授權

原創整合程式碼採 [MIT](LICENSE)，上游作品保留各自的[授權與聲明](THIRD_PARTY_NOTICES.md)。IPA Loom 與 Apple 及上游維護者沒有隸屬關係。發版使用 `v2026.11.9` 等日期標籤，與依賴版本分開。

IPA Loom 標誌是 V-AX 的品牌素材，與程式碼授權分開。詳見[品牌使用說明](BRAND.md)。
