//
// OVIMSmartMandarin.h
//
// Copyright (c) 2004-2010 The OpenVanilla Project (http://openvanilla.org)
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//

#ifndef OVIMSmartMandarin_h
#define OVIMSmartMandarin_h

#ifndef OV_USE_SQLITE
#define OV_USE_SQLITE
#endif

#if defined(__APPLE__)
#include <OpenVanilla/OpenVanilla.h>
#else
#include "OpenVanilla.h"
#endif

#include "Mandarin.h"
#include "Manjusri.h"

namespace OpenVanilla {
using namespace std;
using namespace Formosa::Mandarin;
using namespace Manjusri;

class OVIMSmartMandarin;

// Text to the extra candidates it brings: a candidate's text to its emoji,
// or parts typed in a row to the character they make (水水水 to 淼).
typedef map<string, vector<string> > CandidateTable;

class CandidateFilter {
 public:
  virtual bool shouldPass(const string& text) = 0;
};

class ManjusriComposer {
 public:
  // we don't own lm
  ManjusriComposer(LanguageModel* lm)
      : m_graph(lm /* , 20 */ /* pinyin */),
        m_LM(lm),
        m_cursorLeftBound(0),
        m_cursorRightBound(0),
        m_keysCandidateIndex(string::npos),
        m_keysCandidateBlock(0),
        m_latestCandidateSkipsLearning() {}

  void clear() {
    m_graph.clear();
    m_latestCandidate.clear();
    m_latestCandidateContextPicks.clear();
    update();
  }

  bool insertAt(size_t index, const string qstring, StringFilter* filter = 0) {
    // cerr << "insertAt " << (filter ? "has filter" : "has no filter") << endl;
    return m_graph.insertQueryBlockAndBuild(qstring, index, filter);
  }

  void deleteAt(size_t index, StringFilter* filter = 0) {
    m_graph.removeQueryBlockAndBuild(index, filter);
  }

  void backspaceAt(size_t index, StringFilter* filter = 0) {
    m_graph.removeQueryBlockAndBuild(index - 1, filter);
  }

  bool toggleForcedBreakAt(size_t index, StringFilter* filter = 0) {
    return m_graph.toggleForcedBreakAt(index, filter);
  }

  size_t cursorLeftBound() { return m_cursorLeftBound; }

  size_t cursorRightBound() { return m_cursorRightBound; }

  const string composedString() { return m_composedString; }

  const vector<string> composedStringAsTextSegments() {
    return FastPathAsTextSegments(m_latestFastPath);
  }

  const vector<pair<size_t, size_t> > wordSegments() {
    vector<pair<size_t, size_t> > results;

    if (m_latestFastPath.size() < 3) return results;

    // In characters, not reading blocks; see characterOffsetForCursor().
    size_t offset = 0;
    for (FastPath::const_iterator iter = m_latestFastPath.begin() + 1;
         iter != (m_latestFastPath.end() - 2); ++iter) {
      size_t length = OVUTF8Helper::SplitStringByCodePoint((*iter).text).size();
      results.push_back(pair<size_t, size_t>(offset, length));
      offset += length;
    }

    /*
                if (m_latestPath.size() < 3)
                    return results;

                for (Path::const_iterator iter = m_latestPath.begin() + 1; iter
       != (m_latestPath.end() - 2); ++iter) { Location loc =
       (*(*iter).second).location();

                    results.push_back(pair<size_t, size_t>(loc.first -
       m_cursorLeftBound, loc.second));
                }
    */

    return results;
  }

  const pair<bool, string> shift() {
    if (m_latestFastPath.size() < 3) return pair<bool, string>(false, "");

    const Node& node = *(m_latestFastPath[1].nodePointer);
    const Node& node2 = *(m_latestFastPath[2].nodePointer);

    /*
                if (m_latestPath.size() < 3)
                    return string();

                const StringScoreNodeSetIteratorPair& ssnsip = m_latestPath[1];
                const Node& node = *(ssnsip.second);
                Location loc = node.location(); */

    return m_graph.shiftNodeAndMaintainPathWalk(node, node2);
  }

  // A node's text can run longer than its reading -- a reading picked as the
  // text itself shows two or more characters for one block -- so cursor
  // positions are mapped through the walked path instead of being used as
  // character offsets.
  size_t characterOffsetForCursor(size_t cursor) {
    size_t offset = 0;
    if (m_latestFastPath.size() < 3) return 0;
    for (FastPath::const_iterator iter = m_latestFastPath.begin() + 1;
         iter != (m_latestFastPath.end() - 2); ++iter) {
      Location loc = (*(*iter).nodePointer).location();
      size_t length = OVUTF8Helper::SplitStringByCodePoint((*iter).text).size();
      if (loc.first + loc.second <= cursor) {
        offset += length;
      } else {
        if (loc.first < cursor) offset += min(length, cursor - loc.first);
        break;
      }
    }
    return offset;
  }

  // The last count characters before cursor, or empty unless each is a block
  // of its own (no emoji, reading or passthru word among them). With
  // separateWords, characters walked together as one word don't qualify:
  // 中心 is a word, not 中 and 心 waiting to become 忠.
  string charactersBeforeCursor(size_t cursor, size_t count,
                                bool separateWords) {
    vector<string> characters;
    vector<size_t> nodeOfCharacter;
    if (m_latestFastPath.size() < 3) return string();
    size_t nodeIndex = 0;
    for (FastPath::const_iterator iter = m_latestFastPath.begin() + 1;
         iter != (m_latestFastPath.end() - 2); ++iter, ++nodeIndex) {
      Location loc = (*(*iter).nodePointer).location();
      if (loc.first >= cursor) break;
      vector<string> text = OVUTF8Helper::SplitStringByCodePoint((*iter).text);
      if (text.size() != loc.second) return string();
      size_t take = min(loc.second, cursor - loc.first);
      for (size_t i = 0; i < take; i++) {
        characters.push_back(text[i]);
        nodeOfCharacter.push_back(nodeIndex);
      }
    }
    if (characters.size() < count) return string();
    size_t from = characters.size() - count;
    if (separateWords) {
      for (size_t i = from + 1; i < characters.size(); i++)
        if (nodeOfCharacter[i] == nodeOfCharacter[i - 1]) return string();
    }
    string result;
    for (size_t i = from; i < characters.size(); i++) result += characters[i];
    return result;
  }

  void update() {
    StringVector qblocks = m_graph.queryBlocks();
    if (!qblocks.size()) {
      clear();
      return;
    }

    /*
    // use aggressive walk
    vector<Path> paths = m_graph.walk("", Location(0, 0), true);
    if (!paths.size()) {
        clear();
        return;
    }

    m_latestPath = paths[0];

    */

    m_latestFastPath = m_graph.fastWalk("", Location(0, 0));
    if (!m_latestFastPath.size()) {
      clear();
      return;
    }

    m_cursorLeftBound = 1;
    m_cursorRightBound = qblocks.size() - 1;

    m_composedString = FastPathAsString(m_latestFastPath);

    // cerr << "update result: " << m_latestFastPath << endl;
  }

  // emoji, when given, adds each of the first few candidates' emoji right
  // after that candidate. keyLayout, when given, offers the keys a toneless
  // syllable was typed with, for English that read as Bopomofo (ai as 摸).
  vector<string> collectCandidates(size_t cursor,
                                   bool candidateCursorAtEndOfTargetBlock,
                                   const CandidateTable* emoji = 0,
                                   const BopomofoKeyboardLayout* keyLayout = 0) {
    static const size_t kEmojiSourceCandidates = 5;
    static const size_t kMaxEmojiCandidates = 10;
    vector<string> results;

    // the annotated form lists the same candidates in the same order, so the
    // picks stay aligned by construction rather than by a text lookup
    AnnotatedCandidateVector annotated = m_graph.annotatedCandidatesAtIndex(
        cursor, m_latestFastPath, candidateCursorAtEndOfTargetBlock);

    m_latestCandidate.clear();
    m_latestCandidateContextPicks.clear();
    m_latestCandidateSkipsLearning.clear();
    set<string> offeredEmoji;
    for (AnnotatedCandidateVector::iterator iter = annotated.begin();
         iter != annotated.end(); ++iter) {
      results.push_back((*iter).text);
      m_latestCandidate.push_back(Candidate(
          pair<string, size_t>((*iter).text, (*iter).indexInNode),
          (*iter).node));
      m_latestCandidateContextPicks.push_back((*iter).origin ==
                                              kCandidateOriginBigram);
      m_latestCandidateSkipsLearning.push_back(false);

      if (!emoji || iter - annotated.begin() >= (ptrdiff_t)kEmojiSourceCandidates)
        continue;
      CandidateTable::const_iterator found = emoji->find((*iter).text);
      if (found == emoji->end()) continue;
      for (vector<string>::const_iterator e = found->second.begin();
           e != found->second.end() &&
           offeredEmoji.size() < kMaxEmojiCandidates;
           ++e) {
        if (!offeredEmoji.insert(*e).second) continue;
        // Takes the place of the text it was found for.
        results.push_back(*e);
        m_latestCandidate.push_back(
            Candidate(pair<string, size_t>(*e, 0), (*iter).node));
        m_latestCandidateContextPicks.push_back(false);
        m_latestCandidateSkipsLearning.push_back(true);
      }
    }

    // The reading itself comes last, for when the Bopomofo is what should be
    // typed. It belongs to the block the first candidate replaces.
    bool readingOffered = false;
    if (!annotated.empty()) {
      string reading = ComposedReading((*annotated.front().node).queryString());
      if (reading.size() &&
          find(results.begin(), results.end(), reading) == results.end()) {
        results.push_back(reading);
        m_latestCandidate.push_back(Candidate(pair<string, size_t>(reading, 0),
                                              annotated.front().node));
        m_latestCandidateContextPicks.push_back(false);
        m_latestCandidateSkipsLearning.push_back(true);
        readingOffered = true;
      }
    }

    // The keys go just before the reading. Choosing them is not an override
    // of the node: the caller swaps the block for one passthru per letter, so
    // the entry here only keeps the vectors aligned.
    m_keysCandidateIndex = string::npos;
    if (keyLayout && !annotated.empty()) {
      const Node& node = *annotated.front().node;
      string keys = KeysForBlock(node.queryString(), keyLayout);
      if (node.location().second == 1 && keys.size() &&
          find(results.begin(), results.end(), keys) == results.end()) {
        size_t at = results.size() - (readingOffered ? 1 : 0);
        results.insert(results.begin() + at, keys);
        m_latestCandidate.insert(
            m_latestCandidate.begin() + at,
            Candidate(pair<string, size_t>(keys, 0), annotated.front().node));
        m_latestCandidateContextPicks.insert(
            m_latestCandidateContextPicks.begin() + at, false);
        m_latestCandidateSkipsLearning.insert(
            m_latestCandidateSkipsLearning.begin() + at, true);
        m_keysCandidateIndex = at;
        m_keysCandidateBlock = node.location().first;
        m_keysCandidate = keys;
      }
    }

    return results;
  }

  // The keys candidate of the last collectCandidates() result: its index (npos
  // when there is none), the block it replaces and the keys themselves.
  size_t keysCandidateIndex() const { return m_keysCandidateIndex; }
  size_t keysCandidateBlock() const { return m_keysCandidateBlock; }
  const string& keysCandidate() const { return m_keysCandidate; }
  void forgetKeysCandidate() { m_keysCandidateIndex = string::npos; }

  // aligned with the last collectCandidates() result
  const vector<bool>& latestCandidateContextPicks() const {
    return m_latestCandidateContextPicks;
  }

  size_t chooseCandidate(size_t index,
                         bool shouldUpdate = true,
                         bool shouldLearnFromSelection = true) {
    if (index >= m_latestCandidate.size()) return 0;

    // Typing the reading or an emoji says nothing about which word was meant.
    if (index < m_latestCandidateSkipsLearning.size() &&
        m_latestCandidateSkipsLearning[index])
      shouldLearnFromSelection = false;

    bool shouldCacheSelection = shouldLearnFromSelection;
    Candidate& candi = m_latestCandidate[index];
    const Node& node = *(candi.second);

    // we disallow BPMF symbols
    BPMF bpmf = BPMF::FromComposedString(candi.first.first);
    if (!bpmf.isEmpty()) shouldCacheSelection = false;

    m_graph.overrideNodeCandidate(node /*.location() */, candi.first.first,
                                  shouldCacheSelection);

    if (shouldUpdate) update();

    // remember MSC is more strict on undefined iterator pointer, so we can't go
    // to this path's end, whose node pointer points to graph's m_set's end(),
    // which is a "bad ptr" for MSC
    for (FastPath::iterator fpiter = m_latestFastPath.begin();
         fpiter + 1 != m_latestFastPath.end(); ++fpiter) {
      if ((*(*fpiter).nodePointer).isPreceding(node.location())) {
        string previous = (*(*fpiter).nodePointer).queryString();

        // don't learn from punctuation and friends
        if (!shouldLearnFromSelection ||
            OVWildcard::Match(node.queryString(), "_punctuation_*") ||
            OVWildcard::Match(node.queryString(), "_passthru_*") ||
            OVWildcard::Match(node.queryString(), "_ctrl_*")) {
          continue;
        }

        // The context-keyed override has to be learned here rather than in
        // overrideNodeCandidate(): only the walked path knows which node
        // actually precedes this one. Unlike the bigram below this accepts a
        // BOS predecessor -- "at the start of a sentence" is a real context,
        // and skipping it would leave sentence-initial picks unlearnable,
        // since they could never accumulate the breadth the context-free
        // store now requires. Mirrors the context-free store otherwise: a
        // pick the lexicon would have made anyway needs no override, and
        // clears any stale one.
        if (shouldCacheSelection) {
          if (node.isTextLexiconFirstCandidate(candi.first.first))
            m_LM->removeCachedContextSelection(previous, node.queryString());
          else
            m_LM->cacheContextOverrideSelection(previous, node.queryString(),
                                                candi.first.first);
        }

        if (previous != m_LM->BOSQueryString()) {
          // cerr << "caching user bigram, preceeding text = " << (*fpiter).text
          // << ", our text = " << candi.first.first << ", so qstring: "
          //     << previous << " + " << node.queryString() << endl;
          m_LM->cacheUserBigram(
              m_LM->combineBigramQueryString(previous, node.queryString()),
              (*fpiter).text, candi.first.first);
        }
      }
    }

    return node.location().first + node.location().second;
  }

  const string currentlyMarkedUnigram(size_t from, size_t to) {
    return SVH::Join(
        SVH::SubVector(OVUTF8Helper::SplitStringByCodePoint(m_composedString),
                       from - m_cursorLeftBound, to - from));
  }

  const pair<bool, string> addUserUnigram(size_t from, size_t to) {
    string qstring =
        SVH::Join(SVH::SubVector(m_graph.queryBlocks(), from, to - from));
    string current = SVH::Join(
        SVH::SubVector(OVUTF8Helper::SplitStringByCodePoint(m_composedString),
                       from - m_cursorLeftBound, to - from));

    // cerr << "adding unigram, qstring: " << qstring << ", current: " <<
    // current << endl;
    bool result = m_LM->addUserUnigram(qstring, current);
    return pair<bool, string>(result, current);
  }

  void logStats(OVLoaderService* loaderService) {
    static double accuBuildTime = 0.0;
    static double accuBuildCount = 0;

    // loaderService->logger("ManjusriComposer") << "LM SQL query count: " <<
    // m_LM->queryCount() << ", cached query: " << m_LM->cachedQueryCount() <<
    // ", hit rate: " << (double)m_LM->cachedQueryCount() /
    // (double)(m_LM->queryCount() + m_LM->cachedQueryCount()) * 100.0 << "%" <<
    // endl; loaderService->logger("ManjusriComposer") << "Last build time: " <<
    // m_graph.lastBuildTime() << " secs, walk time: " << m_graph.lastWalkTime()
    // << " secs" << ", build/walk ratio = " << m_graph.lastBuildTime() /
    // m_graph.lastWalkTime() << endl;

    accuBuildTime += m_graph.lastBuildTime();
    accuBuildCount += 1.0;
    // loaderService->logger("ManjusriComposer") << "Avg build time: " <<
    // accuBuildTime / accuBuildCount << " secs" << endl;

    m_LM->resetQueryCount();
  }

 protected:
  Graph m_graph;
  //      Path m_latestPath;
  FastPath m_latestFastPath;

  // Composed Bopomofo for a node made of syllable blocks, or empty when any
  // block is something else (punctuation, passthru text and the like).
  static string ComposedReading(const string& queryString) {
    if (queryString.empty() || queryString.size() % 2 || queryString[0] == '_')
      return string();
    string result;
    for (size_t at = 0; at < queryString.size(); at += 2) {
      BPMF syllable = BPMF::FromAbsoluteOrderString(queryString.substr(at, 2));
      if (syllable.isEmpty()) return string();
      result += syllable.composedString();
    }
    return result;
  }

  // The letters keyLayout types a block's lone toneless syllable with, or
  // empty when the block is anything else or a key is not a letter (天 is
  // wu0). Covers both a syllable block (摸) and the Bopomofo a non-word
  // reading was typed as (ㄕㄟ for go).
  static string KeysForBlock(const string& queryString,
                             const BopomofoKeyboardLayout* keyLayout) {
    static const string kPassthru = "_passthru_";
    BPMF syllable;
    if (queryString.compare(0, kPassthru.size(), kPassthru) == 0) {
      string text = queryString.substr(kPassthru.size());
      while (text.size() && text[text.size() - 1] == ' ')
        text.erase(text.size() - 1);
      syllable = BPMF::FromComposedString(text);
      if (syllable.composedString() != text) return string();
    } else if (queryString.size() == 2 && queryString[0] != '_') {
      syllable = BPMF::FromAbsoluteOrderString(queryString);
    }
    if (syllable.isEmpty() || syllable.hasToneMarker()) return string();

    string keys = keyLayout->keySequenceFromSyllable(syllable);
    if (keys.size() < 2) return string();
    for (size_t i = 0; i < keys.size(); i++)
      if (keys[i] < 'a' || keys[i] > 'z') return string();
    return keys;
  }

  CandidateVector m_latestCandidate;
  size_t m_keysCandidateIndex;
  size_t m_keysCandidateBlock;
  string m_keysCandidate;
  vector<bool> m_latestCandidateContextPicks;
  // aligned with m_latestCandidate: the reading and emoji, never learned
  vector<bool> m_latestCandidateSkipsLearning;
  string m_composedString;

  LanguageModel* m_LM;

  size_t m_cursorLeftBound;
  size_t m_cursorRightBound;
};

class OVIMSmartMandarinContext : public OVEventHandlingContext {
 public:
  OVIMSmartMandarinContext(OVIMSmartMandarin* module);

  virtual void startSession(OVLoaderService* loaderService);
  virtual void stopSession(OVLoaderService* loaderService);
  virtual void clear(OVLoaderService* loaderService);
  virtual bool handleKey(OVKey* key, OVTextBuffer* readingText,
                         OVTextBuffer* composingText,
                         OVCandidateService* candidateService,
                         OVLoaderService* loaderService);

  virtual void candidateCanceled(OVCandidateService* candidateService,
                                 OVTextBuffer* readingText,
                                 OVTextBuffer* composingText,
                                 OVLoaderService* loaderService);
  virtual bool candidateSelected(OVCandidateService* candidateService,
                                 const string& text, size_t index,
                                 OVTextBuffer* readingText,
                                 OVTextBuffer* composingText,
                                 OVLoaderService* loaderService);
  virtual bool candidateNonPanelKeyReceived(
      OVCandidateService* candidateService, const OVKey* key,
      OVTextBuffer* readingText, OVTextBuffer* composingText,
      OVLoaderService* loaderService);

  // aligned with the candidate list last opened, composed characters first
  vector<bool> latestCandidateContextPicks() const {
    vector<bool> picks(m_compositionLengths.size(), false);
    const vector<bool>& collected = m_manjusri.latestCandidateContextPicks();
    picks.insert(picks.end(), collected.begin(), collected.end());
    return picks;
  }

 protected:
  const BopomofoKeyboardLayout* currentKeyboardLayout();
  bool addUserUnigram(size_t from, size_t to, OVTextBuffer* composingText,
                      OVLoaderService* loaderService);
  bool handleQuickUserUnigramKey(const OVKey* key, OVTextBuffer* composingText,
                                 OVLoaderService* loaderService);
  void refreshComposingText(OVTextBuffer* composingText);
  void popOverflowingComposition(OVTextBuffer* composingText,
                                 OVLoaderService* loaderService);

  // Mixed alphanumeric input: keys are read as Bopomofo until the sequence can
  // no longer be one syllable, then the raw keys fall back to ASCII.
  bool mixedAlphanumericActive();
  bool handleMixedAlphanumericKey(OVKey* key, OVTextBuffer* readingText,
                                  OVTextBuffer* composingText,
                                  OVLoaderService* loaderService);
  void appendMixedCharacter(char c, bool forceASCII);
  void rebuildMixedState();
  bool mixedReadingIsComposable(StringFilter* filter);
  void flushMixedASCII(bool appendSpace, StringFilter* filter);
  void clearMixedState();
  void finishMixedEdit(OVTextBuffer* readingText, OVTextBuffer* composingText,
                       bool commitNow, OVLoaderService* loaderService);

  OVIMSmartMandarin* m_module;

  BopomofoReadingBuffer m_BPMFReading;
  ManjusriComposer m_manjusri;
  size_t m_cursor;

  bool m_markMode;
  size_t m_markCursor;

  // Parts each composed candidate replaces, for the composed candidates that
  // lead the open candidate list; see handleKey's candidate window.
  vector<size_t> m_compositionLengths;

  string m_mixedASCIIBuffer;
  // Parallel to m_mixedASCIIBuffer: characters typed as English on purpose
  // (shifted letters), which never count as Bopomofo.
  vector<bool> m_mixedASCIIForced;
  bool m_mixedASCIIMode;
};

class OVIMSmartMandarin : public OVInputMethod {
 public:
  OVIMSmartMandarin();
  ~OVIMSmartMandarin();

  virtual OVEventHandlingContext* createContext();
  virtual const string identifier() const;
  virtual const string localizedName(const string& locale);
  virtual bool initialize(OVPathInfo* pathInfo, OVLoaderService* loaderService);
  virtual void finalize();
  virtual void loadConfig(OVKeyValueMap* moduleConfig,
                          OVLoaderService* loaderService);
  virtual void saveConfig(OVKeyValueMap* moduleConfig,
                          OVLoaderService* loaderService);

 protected:
  friend class OVIMSmartMandarinContext;

 protected:
  LanguageModel* m_LM;
  // OVSQLiteConnection* m_BPMFDB;

  size_t m_cacheFlushKeyCounter;

  // configurable items
  string m_cfgKeyboardLayout;
  string m_cfgCandidateSelectionKeys;
  string m_cfgUseCharactersSupportedByEncoding;
  bool m_cfgShowCandidateListWithSpace;
  bool m_cfgClearComposingTextWithEsc;
  bool m_cfgCandidateCursorAtEndOfTargetBlock;
  bool m_cfgShiftKeyAlwaysCommitUppercaseCharacters;
  bool m_cfgMixedAlphanumericalEnabled;
  bool m_cfgShowEmojiCandidates;
  CandidateTable m_emojiTable;
  CandidateTable m_compositionTable;

  size_t m_cfgComposingTextBufferSize;
};
};  // namespace OpenVanilla

#endif
