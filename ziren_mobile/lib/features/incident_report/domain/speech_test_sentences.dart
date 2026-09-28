/// Fixed sentences to read aloud while testing recognisers.
///
/// Comparing locales only means something when the input is held constant, so
/// these are presets rather than whatever came to mind at the time. Tap one,
/// record it through every candidate locale, read the rows against each other.
///
/// Where the words come from
/// -------------------------
/// The vocabulary is taken from the dataset's own
/// `06_DICTIONARY/emergency_terms.csv` — `sunog`, `nasamdan`, `nagdurugo`,
/// `nabangga` for Waray; `kalayo`, `nasamad`, `naipit`, `nabanggaay` for
/// Cebuano. These are the words the triage model was trained to recognise, so
/// testing them measures the thing that actually matters rather than a
/// recogniser's handling of arbitrary speech.
///
/// Every sentence carries a Biliran place name on purpose. That is the known
/// weak point — no recogniser has `Caibiran` in its vocabulary, and the first
/// live test turned it into `kaibigan`. Holding a municipality in each sentence
/// keeps that failure in view instead of letting a clean-sounding transcript
/// hide it.
///
/// A caveat worth keeping
/// ----------------------
/// The Waray and Cebuano sentences are drafts assembled from that dictionary,
/// not text written by a native speaker. The individual words are sourced; the
/// grammar around them is not vouched for. Correct them in place — the presets
/// are here to be edited, and a sentence a real resident would never say makes
/// for a poor measurement.
class SpeechTestSentences {
  const SpeechTestSentences._();

  static const _byLanguage = <String, List<String>>{
    'Waray': [
      // The sentence from the first live test, kept so the run can be repeated.
      'Mayda sunog didi ha Caibiran',
      'May nasamdan didi ha Naval, nagdurugo',
      'Nabangga an motor didi ha Almeria',
    ],
    'Bisaya': [
      'Naay kalayo dinhi sa Kawayan',
      'Naay nasamad, naipit sa sulod',
      'Nabanggaay ang motor dinhi sa Culaba',
    ],
    'Filipino': [
      'May sunog dito sa Naval, may naiwan sa loob',
      'May nasugatan, dumudugo ang binti',
      'Nabangga ang motor dito sa Cabucgayan',
    ],
    'English': [
      'There is a fire here in Caibiran',
      'Someone is injured and bleeding',
      'A motorcycle crashed here in Maripipi',
    ],
  };

  static List<String> forLanguage(String languageName) =>
      _byLanguage[languageName] ?? const [];

  /// The sentence a fresh run starts on, so the field is never empty.
  static String defaultFor(String languageName) {
    final list = forLanguage(languageName);
    return list.isEmpty ? '' : list.first;
  }
}
