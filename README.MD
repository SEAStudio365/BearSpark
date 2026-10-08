# 熊熊注音 BearSpark

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00?logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/coolfish52)

<img width="256" height="256" alt="熊熊注音" src="Docs/images/bearspark-icon.png" />

一套給 macOS 用的注音輸入法，免費開源。

熊熊注音改作自 [千秋輸入法 ChiaKey](https://github.com/chiakich/ChiaKey)。千秋輸入法延續了 Yahoo! 奇摩輸入法的打字手感，熊熊注音在這個基礎上，把選字窗改得更像 macOS 內建注音，再補上幾個日常打字會用到的功能：不切換就能打英文、Emoji 候選、拆字組字。

## 跟千秋輸入法哪裡不一樣

- **接近系統原生的選字窗**：樣式和大小貼近 macOS 內建注音。一排顯示 9 個候選字，按 <kbd>↓</kbd> 或點右邊的 ⌄ 往上展開成大選字窗（一排 6 個），在第一排按 <kbd>↑</kbd> 收回。候選字少於 9 個時不會展開。
- **滑鼠點選候選字**：直接點就能選，不需要開「輔助使用」之類的權限。
- **不切換也能打英文**：中文打到一半直接打英文單字，不用先切到英文模式。在偏好設定勾選「不切換也能打英文（中英混打）」。注音還沒打聲調就按 Enter，送出的是打的字母（`g` 不會變成「師」）。英文剛好拼成注音時（例如 `ai` 按空白打出「摸」），按 ↓ 叫出選字窗，右邊的小方塊裡有原本打的英文，按 <kbd>Tab</kbd> 或用滑鼠點就能換回來。
- **Emoji 候選**：打「貓」「愛心」「生日」這類詞，候選字裡會出現對應的 Emoji。在偏好設定勾選「候選字顯示 emoji」。
- **注音本身也是候選**：注音符號放在選字窗右邊的小方塊，翻到哪一頁都在。需要打出注音時按 <kbd>Tab</kbd> 或直接點。
- **拆字組字**：依筆順打出部件再叫出選字窗，就能組出整個字，例如「水水水」→ 淼、「木木木」→ 森、「日月」→ 明。
- **擴充區罕用字**：在偏好設定勾選「顯示擴充 B 區以後的罕用字」，詞庫沒收的罕用字也能用注音打出來，例如打 ㄗㄞ 會出現 𢦏，排在同音字後面。需要另外安裝收有這些字的字型才看得到，例如數位發展部的[全字庫字型](https://data.gov.tw/dataset/5961)。
- **聯想詞**：選完字後出現的聯想詞，可以用滑鼠點，也能展開成大選字窗。
- **macOS 風格的通知**：切換模式時的提示改成系統通知的樣式，在新版 macOS 上是透明玻璃效果。

## 下載安裝

到 [GitHub Releases](https://github.com/SEAStudio365/BearSpark/releases) 下載最新的 `.pkg` 安裝檔。

安裝包會裝到目前使用者的 `~/Library/Input Methods`，不需要管理員權限。第一次安裝完要**登出再登入**，之後到「系統設定 > 鍵盤 > 文字輸入 > 編輯 > +」，選「繁體中文 > 熊熊注音」加入。


### 解除安裝

在「熊熊注音偏好設定」的「更新」分頁按「移除熊熊注音…」。預設會保留自訂詞與設定，勾選「同時刪除使用者自訂詞與設定」則全部清除。


## 從千秋輸入法繼承的功能

這些功能來自千秋輸入法，熊熊注音照樣保留：

- **從 Yahoo! 奇摩輸入法搬家**：在偏好設定的「詞彙管理」按「匯入 Yahoo! 奇摩輸入法資料…」，把自訂詞和選字記錄帶過來。舊版程式必須還能執行（M 系列晶片需要 Rosetta 2）。
- **匯入 .cin 表格**：在偏好設定的「自訂輸入法」按 + 匯入倉頡、行列、大易、粵拼等 `.cin` 表格。表格存在 `~/Library/Application Support/BearSpark/DataTables/Generic/`。
- **倉頡、簡易**等內建輸入法，以及詞彙編輯器。

熊熊注音的設定與自訂詞存在 `~/Library/Application Support/BearSpark`，跟千秋輸入法分開，兩套可以同時安裝。

## 詞庫

熊熊注音使用 [千秋輸入法綜合詞庫](https://github.com/chiakich/ChiaKey-Lexicon)（CC BY-NC 4.0），由千秋重建的 bigram 語言模型，選字品質主要來自這裡。

遇到缺詞或選錯字，屬於詞庫的問題，請到 [ChiaKey-Lexicon](https://github.com/chiakich/ChiaKey-Lexicon/issues) 回報。
輸入法本身的問題（打不出字、當掉、選字窗異常）請到 [這裡回報](https://github.com/SEAStudio365/BearSpark/issues/new/choose)。

## 隱私

打字完全離線。熊熊注音只會在檢查詞庫更新時連到 GitHub，不會送出你打的字、自訂詞或學習記錄。

## 致謝與授權

熊熊注音站在這些專案的肩膀上：

- [千秋輸入法 ChiaKey](https://github.com/chiakich/ChiaKey)：涼風千秋 Chiaki.C 的 Yahoo! 奇摩輸入法復興專案，熊熊注音的直接上游
- [Yahoo! KeyKey](https://github.com/YahooArchive/KeyKey) 與 [OpenVanilla](https://openvanilla.org/)：輸入法引擎的起源
- [vChewing 唯音輸入法](https://github.com/vChewing/vChewing-macOS)：選字窗樣式與中英混打的參考
- [Unicode CLDR](https://cldr.unicode.org/)：Emoji 的中文關鍵字（Unicode License v3）
- [Unicode Unihan](https://www.unicode.org/charts/unihan.html)：擴充區罕用字的讀音（Unicode License v3）

原始碼依 BSD-style 授權釋出，詳見 [LICENSE](LICENSE)。熊熊注音不是 Yahoo! 或千秋輸入法的官方產品，未受其贊助、認可或背書。

由 [SEAStudio](https://github.com/SEAStudio365) 製作。

---

**關鍵字：** macOS 注音輸入法、Mac 注音、Yahoo 奇摩輸入法替代、千秋輸入法、中英混打、注音 Emoji、拆字輸入、開源輸入法、臺灣輸入法
