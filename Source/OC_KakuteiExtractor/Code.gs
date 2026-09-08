/**
 * @OnlyCurrentDoc
 *
 * OC_KakuteiExtractor
 *
 * 「学生情報一覧」から指定期間の学生情報を抽出し、フリガナ順の
 * ヘッダーなしTSVをクリップボードへコピーする。
 *
 * Apps Scriptプロジェクト全体での字句宣言衝突を避けるため、
 * トップレベルにはconst、let、varを宣言しない。
 */

/**
 * 実行時設定を生成する。
 *
 * @return {Object} 実行時設定。
 */
function ocKakuteiGetConfig_() {
  return {
    toolName: 'OC_KakuteiExtractor',
    controlSheetName: 'スクリプト用シート',
    sourceSheetName: '学生情報一覧',
    dateInputRangeA1: 'A2:B2',
    startDateCellA1: 'A2',
    endDateCellA1: 'B2',
    headerSearchStartRow: 1,
    fixedHeaders: ['学籍番号', '名前', 'フリガナ', 'SA/TA'],
    allowedStatusValues: ['〇', '×', 'キャンセル', '確定', '定員'],
    allowBlankSaTa: true,
    allowBlankDateValues: true,
    maxStudents: 1000,
    maxDateColumns: 300,
    maxReadCells: 500000,
    maxRangeYears: 3,
    lockTimeoutMs: 5000,
    copyDialogFile: 'コピー確認',
    copyDialogWidth: 720,
    copyDialogHeight: 640,
  };
}

/**
 * スプレッドシート上の実行ボタンへ割り当てる公開関数。
 */
function runOC_KakuteiExtractor() {
  var config = ocKakuteiGetConfig_();
  var ui = SpreadsheetApp.getUi();
  var documentLock = null;
  var lockHeld = false;

  try {
    var initialContext = ocKakuteiReadAndValidateContext_(config, false);
    var response = ui.alert(
      config.toolName,
      ocKakuteiBuildInitialConfirmationMessage_(config, initialContext),
      ui.ButtonSet.YES_NO,
    );

    if (response !== ui.Button.YES) {
      return;
    }

    documentLock = LockService.getDocumentLock();
    if (!documentLock || !documentLock.tryLock(config.lockTimeoutMs)) {
      ocKakuteiShowAlert_(
        config,
        ui,
        '別の処理が実行中です。完了後に再実行してください。',
      );
      return;
    }
    lockHeld = true;

    // 確認画面の表示中はロックが維持されないため、ロック取得後に再検証する。
    var currentContext = ocKakuteiReadAndValidateContext_(config, true);
    if (initialContext.snapshotHash !== currentContext.snapshotHash) {
      ocKakuteiThrowUserError_(
        '確認中に入力、ヘッダー行または学生情報が変更されました。' +
        '内容を確認して再実行してください。',
      );
    }

    ocKakuteiResetSourceSheetView_(config, currentContext.sourceSheet);
    var output = ocKakuteiBuildCopyOutput_(currentContext.records);

    SpreadsheetApp.flush();
    documentLock.releaseLock();
    lockHeld = false;

    ocKakuteiShowCopyDialog_(config, currentContext, output);
  } catch (error) {
    if (lockHeld && documentLock) {
      try {
        SpreadsheetApp.flush();
      } catch (flushError) {
        // 元の例外を優先し、学生情報はログへ出力しない。
      }
      try {
        documentLock.releaseLock();
      } catch (releaseError) {
        // 元の例外を優先し、学生情報はログへ出力しない。
      }
    }

    ocKakuteiShowAlert_(config, ui, ocKakuteiToUserMessage_(error));
  }
}

/**
 * 入力、シート構成、ヘッダー、学生データを取得して検証する。
 *
 * @param {Object} config 実行時設定。
 * @param {boolean} retainRecords コピー用レコードを保持するか。
 * @return {Object} 検証済みコンテキスト。
 */
function ocKakuteiReadAndValidateContext_(config, retainRecords) {
  var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    ocKakuteiThrowUserError_('実行対象のスプレッドシートを取得できませんでした。');
  }

  var controlSheet = spreadsheet.getActiveSheet();
  if (!controlSheet || controlSheet.getName() !== config.controlSheetName) {
    ocKakuteiThrowUserError_('「スクリプト用シート」から実行してください。');
  }

  var sourceSheet = spreadsheet.getSheetByName(config.sourceSheetName);
  if (!sourceSheet) {
    ocKakuteiThrowUserError_('「学生情報一覧」シートが見つかりません。');
  }

  var dateInputs = controlSheet
    .getRange(config.dateInputRangeA1)
    .getDisplayValues()[0];
  var startText = String(dateInputs[0]).trim();
  var endText = String(dateInputs[1]).trim();

  if (startText === '') {
    ocKakuteiThrowUserError_(
      '開始日を入力してください。対象セル: ' + config.startDateCellA1,
    );
  }
  if (endText === '') {
    ocKakuteiThrowUserError_(
      '終了日を入力してください。対象セル: ' + config.endDateCellA1,
    );
  }

  var startDate = ocKakuteiParseStrictInputDate_(startText, '開始日');
  var endDate = ocKakuteiParseStrictInputDate_(endText, '終了日');
  if (startDate.key > endDate.key) {
    ocKakuteiThrowUserError_('開始日は終了日以前の日付にしてください。');
  }
  ocKakuteiValidateMaximumDateRange_(config, startDate, endDate);

  var lastColumn = sourceSheet.getLastColumn();
  var lastRow = sourceSheet.getLastRow();
  if (lastColumn < 1 || lastRow < config.headerSearchStartRow) {
    ocKakuteiThrowUserError_('「学生情報一覧」にデータがありません。');
  }

  var readRows = lastRow - config.headerSearchStartRow + 1;
  ocKakuteiValidateReadSize_(config, readRows, lastColumn);

  // ヘッダー行検索と学生データ取得は表示文字列を一括取得して行う。
  var displayMatrix = sourceSheet
    .getRange(
      config.headerSearchStartRow,
      1,
      readRows,
      lastColumn,
    )
    .getDisplayValues();

  var headerLocation = ocKakuteiFindHeaderRow_(
    config,
    displayMatrix,
    config.headerSearchStartRow,
  );
  var headerRow = headerLocation.rowNumber;
  var headerMatrixIndex = headerLocation.matrixIndex;
  var displayHeaders = displayMatrix[headerMatrixIndex].map(function (value) {
    return String(value);
  });

  // 日付見出しは表示が「4/19」でも、セル実体が日付なら年を含めて判定する。
  var rawHeaders = sourceSheet
    .getRange(headerRow, 1, 1, lastColumn)
    .getValues()[0];
  var spreadsheetTimeZone =
    spreadsheet.getSpreadsheetTimeZone() || 'Asia/Tokyo';
  var headerInfo = ocKakuteiAnalyzeHeaders_(
    config,
    displayHeaders,
    rawHeaders,
    spreadsheetTimeZone,
    startDate,
    endDate,
  );

  var dataStartRow = headerRow + 1;
  var rowResult = ocKakuteiValidateStudentRows_(
    config,
    displayMatrix,
    headerInfo,
    dataStartRow,
    retainRecords,
    headerMatrixIndex + 1,
    0,
  );

  // 取得対象外の追加列はスナップショットに含めない。
  var fingerprintPayload = {
    spreadsheetId: spreadsheet.getId(),
    spreadsheetName: spreadsheet.getName(),
    controlSheetId: controlSheet.getSheetId(),
    sourceSheetId: sourceSheet.getSheetId(),
    spreadsheetTimeZone: spreadsheetTimeZone,
    startText: startDate.text,
    endText: endDate.text,
    headerRow: headerRow,
    dataStartRow: dataStartRow,
    headerSignature: headerInfo.headerSignature,
    relevantRows: rowResult.fingerprintRows,
  };

  return {
    spreadsheet: spreadsheet,
    spreadsheetName: spreadsheet.getName(),
    controlSheet: controlSheet,
    sourceSheet: sourceSheet,
    headerRow: headerRow,
    dataStartRow: dataStartRow,
    startDate: startDate,
    endDate: endDate,
    dateLabels: headerInfo.targetDateColumns.map(function (column) {
      return column.confirmationLabel;
    }),
    rowCount: rowResult.studentCount,
    records: retainRecords ? rowResult.records : null,
    snapshotHash: ocKakuteiSha256Hex_(JSON.stringify(fingerprintPayload)),
  };
}

/**
 * 使用範囲を配列として取得する前に、読み込み量を制限する。
 * 業務上の学生数・日付列数の検証とは独立した資源上限。
 */
function ocKakuteiValidateReadSize_(config, rows, columns) {
  if (
    !Number.isSafeInteger(config.maxReadCells) || config.maxReadCells < 1 ||
    !Number.isSafeInteger(rows) || rows < 1 ||
    !Number.isSafeInteger(columns) || columns < 1
  ) {
    ocKakuteiThrowUserError_('読み込み範囲または読み込み上限の設定が不正です。');
  }
  if (rows > Math.floor(config.maxReadCells / columns)) {
    ocKakuteiThrowUserError_(
      '読み込み対象が上限の' + config.maxReadCells +
      'セルを超えています。学生情報一覧の不要な遠方セルや追加列を整理してください。',
    );
  }
}

/**
 * 必須4列名が同一行に1回ずつ存在する唯一の行を検索する。
 */
function ocKakuteiFindHeaderRow_(config, displayMatrix, firstSheetRow) {
  var validCandidates = [];
  var duplicateCandidates = [];

  for (var matrixIndex = 0; matrixIndex < displayMatrix.length; matrixIndex += 1) {
    var row = displayMatrix[matrixIndex].map(function (value) {
      return String(value);
    });
    var counts = {};

    config.fixedHeaders.forEach(function (headerName) {
      counts[headerName] = 0;
    });
    row.forEach(function (value) {
      if (Object.prototype.hasOwnProperty.call(counts, value)) {
        counts[value] += 1;
      }
    });

    var hasAllRequiredHeaders = config.fixedHeaders.every(function (headerName) {
      return counts[headerName] >= 1;
    });
    if (!hasAllRequiredHeaders) {
      continue;
    }

    var candidate = {
      matrixIndex: matrixIndex,
      rowNumber: firstSheetRow + matrixIndex,
    };
    var hasDuplicateRequiredHeader = config.fixedHeaders.some(
      function (headerName) {
        return counts[headerName] > 1;
      },
    );

    if (hasDuplicateRequiredHeader) {
      duplicateCandidates.push(candidate);
    } else {
      validCandidates.push(candidate);
    }
  }

  if (duplicateCandidates.length > 0) {
    ocKakuteiThrowUserError_(
      '必須列名が全て存在しますが、同じ必須列名が複数ある行があります。対象行: ' +
      ocKakuteiFormatRowNumberList_(duplicateCandidates.map(function (candidate) {
        return candidate.rowNumber;
      })),
    );
  }

  if (validCandidates.length === 0) {
    ocKakuteiThrowUserError_(
      '必須列「' + config.fixedHeaders.join('」「') +
      '」が全て揃うヘッダー行が見つかりません。',
    );
  }

  if (validCandidates.length > 1) {
    ocKakuteiThrowUserError_(
      '必須列名が全て存在するヘッダー行が複数見つかりました。対象行: ' +
      ocKakuteiFormatRowNumberList_(validCandidates.map(function (candidate) {
        return candidate.rowNumber;
      })),
    );
  }

  return validCandidates[0];
}

/**
 * 採用したヘッダー行から固定列と日付列を特定する。
 */
function ocKakuteiAnalyzeHeaders_(
  config,
  displayHeaders,
  rawHeaders,
  spreadsheetTimeZone,
  startDate,
  endDate
) {
  var fixedHeaderPositions = {};
  var dateColumns = [];
  var dateColumnByKey = {};

  config.fixedHeaders.forEach(function (headerName) {
    fixedHeaderPositions[headerName] = [];
  });

  for (var index = 0; index < displayHeaders.length; index += 1) {
    var displayValue = String(displayHeaders[index]);

    if (Object.prototype.hasOwnProperty.call(fixedHeaderPositions, displayValue)) {
      fixedHeaderPositions[displayValue].push(index);
      continue;
    }

    var parsedHeaderDate = ocKakuteiParseHeaderDate_(
      displayValue,
      rawHeaders[index],
      spreadsheetTimeZone,
      index + 1,
    );
    if (!parsedHeaderDate) {
      continue;
    }

    if (Object.prototype.hasOwnProperty.call(
      dateColumnByKey,
      String(parsedHeaderDate.key),
    )) {
      ocKakuteiThrowUserError_(
        '同じ日付の列が複数存在します: ' +
        parsedHeaderDate.canonicalText,
      );
    }

    var dateColumn = {
      index: index,
      key: parsedHeaderDate.key,
      canonicalText: parsedHeaderDate.canonicalText,
      displayLabel: displayValue,
      confirmationLabel: ocKakuteiBuildDateConfirmationLabel_(
        displayValue,
        parsedHeaderDate.canonicalText,
      ),
    };
    dateColumnByKey[String(parsedHeaderDate.key)] = dateColumn;
    dateColumns.push(dateColumn);
  }

  config.fixedHeaders.forEach(function (headerName) {
    var positions = fixedHeaderPositions[headerName];
    if (positions.length === 0) {
      ocKakuteiThrowUserError_('必須列「' + headerName + '」が見つかりません。');
    }
    if (positions.length > 1) {
      ocKakuteiThrowUserError_('必須列「' + headerName + '」が複数存在します。');
    }
  });

  if (dateColumns.length > config.maxDateColumns) {
    ocKakuteiThrowUserError_(
      '日付列数が上限の' + config.maxDateColumns +
      '列を超えています。現在の日付列数: ' + dateColumns.length + '列',
    );
  }

  var targetDateColumns = dateColumns.filter(function (column) {
    return startDate.key <= column.key && column.key <= endDate.key;
  });
  if (targetDateColumns.length === 0) {
    ocKakuteiThrowUserError_(
      '指定期間内の日付列が見つかりません。' +
      '日付見出しセルはGoogle スプレッドシートの日付値として入力するか、' +
      '年を含む yyyy/M/d 形式で入力してください。' +
      '表示が4/19でも内部値が日付なら認識できます。',
    );
  }

  var fixedIndexes = config.fixedHeaders.map(function (headerName) {
    return fixedHeaderPositions[headerName][0];
  });
  var outputIndexes = fixedIndexes.concat(
    targetDateColumns.map(function (column) {
      return column.index;
    }),
  );
  var dataStartIndex = Math.min.apply(null, outputIndexes);
  var dataEndIndex = Math.max.apply(null, outputIndexes);

  return {
    fixedIndexes: fixedIndexes,
    studentIdIndex: fixedHeaderPositions['学籍番号'][0],
    nameIndex: fixedHeaderPositions['名前'][0],
    furiganaIndex: fixedHeaderPositions['フリガナ'][0],
    saTaIndex: fixedHeaderPositions['SA/TA'][0],
    dateColumns: dateColumns,
    targetDateColumns: targetDateColumns,
    outputIndexes: outputIndexes,
    dataStartIndex: dataStartIndex,
    dataWidth: dataEndIndex - dataStartIndex + 1,
    headerSignature: {
      fixed: config.fixedHeaders.map(function (headerName, fixedIndex) {
        return [headerName, fixedIndexes[fixedIndex]];
      }),
      dates: dateColumns.map(function (column) {
        return [column.canonicalText, column.index, column.displayLabel];
      }),
    },
  };
}

/**
 * ヘッダーセルを日付として解析する。
 *
 * @return {Object|null} 日付情報。日付列でなければnull。
 */
function ocKakuteiParseHeaderDate_(
  displayValue,
  rawValue,
  spreadsheetTimeZone,
  columnNumber
) {
  if (ocKakuteiIsValidDateObject_(rawValue)) {
    var canonicalFromDate = Utilities.formatDate(
      rawValue,
      spreadsheetTimeZone,
      'yyyy/MM/dd',
    );
    return ocKakuteiParseCanonicalDate_(
      canonicalFromDate,
      columnNumber + '列目の日付ヘッダー',
    );
  }

  var text = String(displayValue).trim();
  if (!/^\d{4}\/\d{1,2}\/\d{1,2}$/.test(text)) {
    return null;
  }

  return ocKakuteiParseFullYearDateText_(
    text,
    columnNumber + '列目の日付ヘッダー',
  );
}

/**
 * 入力欄用の厳密なyyyy/MM/dd日付解析。
 */
function ocKakuteiParseStrictInputDate_(value, label) {
  var text = String(value).trim();
  if (!/^\d{4}\/\d{2}\/\d{2}$/.test(text)) {
    ocKakuteiThrowUserError_(
      label + 'は yyyy/MM/dd 形式で入力してください: ' +
      ocKakuteiPrintableValue_(text),
    );
  }
  return ocKakuteiParseCanonicalDate_(text, label);
}

/**
 * 年を含むyyyy/M/dまたはyyyy/MM/ddを解析し、正規化する。
 */
function ocKakuteiParseFullYearDateText_(value, label) {
  var text = String(value).trim();
  var match = /^(\d{4})\/(\d{1,2})\/(\d{1,2})$/.exec(text);
  if (!match) {
    ocKakuteiThrowUserError_(
      label + 'は年を含む yyyy/M/d 形式で入力してください: ' +
      ocKakuteiPrintableValue_(text),
    );
  }

  return ocKakuteiBuildDateParts_(
    Number(match[1]),
    Number(match[2]),
    Number(match[3]),
    label,
    text,
  );
}

/**
 * 正規化済みyyyy/MM/ddを解析する。
 */
function ocKakuteiParseCanonicalDate_(value, label) {
  var text = String(value).trim();
  var match = /^(\d{4})\/(\d{2})\/(\d{2})$/.exec(text);
  if (!match) {
    ocKakuteiThrowUserError_(label + 'の日付形式を解析できませんでした: ' + text);
  }

  return ocKakuteiBuildDateParts_(
    Number(match[1]),
    Number(match[2]),
    Number(match[3]),
    label,
    text,
  );
}

function ocKakuteiBuildDateParts_(year, month, day, label, originalText) {
  var key = Date.UTC(year, month - 1, day);
  var date = new Date(key);

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    ocKakuteiThrowUserError_(
      label + 'として入力された日付は存在しません: ' + originalText,
    );
  }

  var canonicalText = [
    String(year).padStart(4, '0'),
    String(month).padStart(2, '0'),
    String(day).padStart(2, '0'),
  ].join('/');

  return {
    text: canonicalText,
    canonicalText: canonicalText,
    year: year,
    month: month,
    day: day,
    key: key,
  };
}

function ocKakuteiBuildDateConfirmationLabel_(displayValue, canonicalText) {
  var displayText = String(displayValue).trim();
  if (displayText === '' || displayText === canonicalText) {
    return canonicalText;
  }
  return displayText + '（' + canonicalText + '）';
}

function ocKakuteiIsValidDateObject_(value) {
  return Object.prototype.toString.call(value) === '[object Date]' &&
    !isNaN(value.getTime());
}

/**
 * 学生行を検証し、必要に応じてコピー用レコードを保持する。
 *
 * 学籍番号は必須。SA/TAと対象日付セルは空欄を許容する。
 */
function ocKakuteiValidateStudentRows_(
  config,
  displayRows,
  headerInfo,
  firstSheetRow,
  retainRecords,
  matrixStartIndex,
  sourceColumnOffset
) {
  matrixStartIndex = matrixStartIndex === undefined ? 0 : matrixStartIndex;
  sourceColumnOffset = sourceColumnOffset === undefined
    ? headerInfo.dataStartIndex : sourceColumnOffset;
  var records = [];
  var fingerprintRows = [];
  var studentCount = 0;
  var outputLabels = config.fixedHeaders.concat(
    headerInfo.targetDateColumns.map(function (column) {
      return column.confirmationLabel;
    }),
  );

  for (var offset = matrixStartIndex; offset < displayRows.length; offset += 1) {
    var sheetRow = firstSheetRow + offset - matrixStartIndex;
    var sourceRow = displayRows[offset];
    var valueAt = function (sourceColumnIndex) {
      return String(sourceRow[sourceColumnIndex - sourceColumnOffset]);
    };
    var rawOutputValues = headerInfo.outputIndexes.map(function (outputIndex) {
      return valueAt(outputIndex);
    });

    var rawStudentId = valueAt(headerInfo.studentIdIndex);
    var studentId = ocKakuteiNormalizeIdentifier_(rawStudentId);
    var hasOtherRelevantValue = rawOutputValues.slice(1).some(function (value) {
      return !ocKakuteiIsBlankDisplayValue_(value);
    });

    if (studentId === '') {
      if (hasOtherRelevantValue) {
        ocKakuteiThrowUserError_(
          'シート上の' + sheetRow + '行目（対象セル ' +
          ocKakuteiBuildCellA1_(sheetRow, headerInfo.studentIdIndex) +
          '）は学籍番号が空欄ですが、他の取得対象列に値があります。',
        );
      }
      continue;
    }

    studentCount += 1;
    if (studentCount > config.maxStudents) {
      ocKakuteiThrowUserError_(
        '学生数が上限の' + config.maxStudents +
        '人を超えています。現在の学生数: ' + studentCount + '人以上',
      );
    }

    studentId = ocKakuteiValidateRequiredAsciiAlphanumeric_(
      rawStudentId,
      sheetRow,
      headerInfo.studentIdIndex,
      '学籍番号',
    );

    var name = valueAt(headerInfo.nameIndex);
    if (name.trim() === '') {
      ocKakuteiThrowUserError_(
        'シート上の' + sheetRow + '行目（対象セル ' +
        ocKakuteiBuildCellA1_(sheetRow, headerInfo.nameIndex) +
        '）の「名前」が空欄です。',
      );
    }

    var furigana = valueAt(headerInfo.furiganaIndex);
    ocKakuteiValidateFurigana_(
      furigana,
      sheetRow,
      headerInfo.furiganaIndex,
    );

    var rawSaTa = valueAt(headerInfo.saTaIndex);
    var saTa = config.allowBlankSaTa
      ? ocKakuteiValidateOptionalAsciiAlphanumeric_(
        rawSaTa,
        sheetRow,
        headerInfo.saTaIndex,
        'SA/TA',
      )
      : ocKakuteiValidateRequiredAsciiAlphanumeric_(
        rawSaTa,
        sheetRow,
        headerInfo.saTaIndex,
        'SA/TA',
      );

    // 出力順は必須4列、対象日付列の順で固定されている。
    var outputValues = rawOutputValues;
    outputValues[config.fixedHeaders.indexOf('学籍番号')] = studentId;
    outputValues[config.fixedHeaders.indexOf('SA/TA')] = saTa;

    headerInfo.targetDateColumns.forEach(function (column, dateIndex) {
      var value = valueAt(column.index);
      var normalizedValue = ocKakuteiNormalizeOptionalDateValue_(value);

      if (
        normalizedValue !== '' &&
        config.allowedStatusValues.indexOf(normalizedValue) === -1
      ) {
        var cellA1 = ocKakuteiBuildCellA1_(sheetRow, column.index);
        ocKakuteiThrowUserError_(
          'シート上の' + sheetRow + '行目（対象セル ' + cellA1 +
          '）の「' + column.confirmationLabel +
          '」に許可されていない値があります。検出値: ' +
          ocKakuteiDescribeValue_(value),
        );
      }

      if (normalizedValue === '' && !config.allowBlankDateValues) {
        var blankCellA1 = ocKakuteiBuildCellA1_(sheetRow, column.index);
        ocKakuteiThrowUserError_(
          'シート上の' + sheetRow + '行目（対象セル ' + blankCellA1 +
          '）の「' + column.confirmationLabel + '」が空欄です。',
        );
      }

      outputValues[config.fixedHeaders.length + dateIndex] = normalizedValue;
    });

    ocKakuteiValidateNoTsvControlCharacters_(
      config,
      outputValues,
      sheetRow,
      headerInfo,
      outputLabels,
    );

    fingerprintRows.push(ocKakuteiFingerprintRow_(sheetRow, outputValues));
    if (retainRecords) {
      records.push({
        sourceRow: sheetRow,
        sortKey: ocKakuteiNormalizeFuriganaForSort_(furigana),
        values: outputValues,
      });
    }
  }

  if (studentCount === 0) {
    ocKakuteiThrowUserError_('コピー対象となる学生データがありません。');
  }

  return {
    studentCount: studentCount,
    records: records,
    fingerprintRows: fingerprintRows,
  };
}

/** コピーと指紋で値配列を共有し、JSON化するときだけ1行分を平坦化する。 */
function ocKakuteiFingerprintRow_(sheetRow, values) {
  return {
    toJSON: function () {
      return [sheetRow].concat(values);
    },
  };
}

/**
 * TSVを生成する。
 */
function ocKakuteiBuildCopyOutput_(records) {
  var sortedRecords = records.slice().sort(function (left, right) {
    var compared = left.sortKey.localeCompare(right.sortKey, 'ja');
    if (compared !== 0) {
      return compared;
    }
    return left.sourceRow - right.sourceRow;
  });

  return {
    rowCount: sortedRecords.length,
    copyText: sortedRecords.map(function (record) {
      return record.values.join('\t');
    }).join('\n'),
  };
}

/**
 * 通常フィルタの絞り込み条件だけを解除し、フィルタ本体は保持する。
 * 手動で非表示にされた行を再表示する。
 *
 * 行グループは通常の非表示行とは別機能として扱い、開閉状態を変更しない。
 * 抽出処理は表示状態に依存せず、対象データを配列から取得する。
 */
function ocKakuteiResetSourceSheetView_(config, sourceSheet) {
  var filterState = ocKakuteiCaptureStandardFilterState_(sourceSheet);

  ocKakuteiAssertViewResetPermission_(sourceSheet);
  ocKakuteiRevealManualHiddenRowsSafely_(sourceSheet);

  if (!filterState.filter || filterState.criteria.length === 0) {
    return;
  }

  ocKakuteiClearStandardFilterCriteriaSafely_(filterState);
}

/**
 * 通常フィルタと列条件を読み取り専用で退避する。
 */
function ocKakuteiCaptureStandardFilterState_(sourceSheet) {
  try {
    var filter = sourceSheet.getFilter();
    if (!filter) {
      return {
        filter: null,
        criteria: [],
      };
    }

    var filterRange = filter.getRange();
    var firstColumn = filterRange.getColumn();
    var columnCount = filterRange.getNumColumns();
    var criteria = [];

    for (var offset = 0; offset < columnCount; offset += 1) {
      var columnPosition = firstColumn + offset;
      var columnCriteria = filter.getColumnFilterCriteria(columnPosition);
      if (columnCriteria) {
        criteria.push({
          columnPosition: columnPosition,
          criteria: columnCriteria.copy().build(),
        });
      }
    }

    return {
      filter: filter,
      criteria: criteria,
    };
  } catch (error) {
    ocKakuteiThrowUserError_(
      '通常フィルタの状態を読み取れませんでした。' +
      'フィルタ本体、絞り込み条件、行の表示状態は変更していません。' +
      '編集権限とフィルタ範囲を確認してください。',
    );
  }
}

/**
 * シート保護によって表示状態を変更できないことが明白な場合、
 * いかなる表示変更も行う前に中止する。
 */
function ocKakuteiAssertViewResetPermission_(sourceSheet) {
  try {
    var protections = sourceSheet.getProtections(
      SpreadsheetApp.ProtectionType.SHEET,
    );
    var blockingProtection = protections.some(function (protection) {
      return !protection.isWarningOnly() && !protection.canEdit();
    });

    if (blockingProtection) {
      ocKakuteiThrowUserError_(
        '「学生情報一覧」はシート保護されており、' +
        '実行ユーザーには行の再表示またはフィルタ条件の変更権限がありません。' +
        'フィルタ本体、絞り込み条件、行の表示状態は変更していません。' +
        'シートの所有者または保護範囲の管理者に権限を確認してください。',
      );
    }
  } catch (error) {
    if (error && error.name === 'OC_KakuteiExtractorUserError') {
      throw error;
    }
    ocKakuteiThrowUserError_(
      '「学生情報一覧」の保護状態を確認できませんでした。' +
      'フィルタ本体、絞り込み条件、行の表示状態は変更していません。' +
      '編集権限を確認してください。',
    );
  }
}

/**
 * 手動で非表示にされた行を再表示する。
 *
 * 行グループの展開APIは、行グループが存在しないシートでも例外となる
 * 場合があるため呼び出さない。グループの開閉状態は保持する。
 */
function ocKakuteiRevealManualHiddenRowsSafely_(sourceSheet) {
  var maxRows = sourceSheet.getMaxRows();

  try {
    if (maxRows > 0) {
      sourceSheet.showRows(1, maxRows);
    }
    SpreadsheetApp.flush();
  } catch (error) {
    ocKakuteiThrowUserError_(
      '手動で非表示にされた行を再表示できませんでした。' +
      '通常フィルタ本体と絞り込み条件は変更していません。' +
      '行グループの開閉状態も変更していません。' +
      'シート保護、編集権限、結合セルなどを確認してください。',
    );
  }
}

/**
 * 既存の通常フィルタを残したまま、各列の絞り込み条件だけを解除する。
 * 途中で失敗した場合は、退避した条件を復元する。
 */
function ocKakuteiClearStandardFilterCriteriaSafely_(filterState) {
  try {
    filterState.criteria.forEach(function (entry) {
      filterState.filter.removeColumnFilterCriteria(entry.columnPosition);
    });
    SpreadsheetApp.flush();
  } catch (error) {
    var restored = ocKakuteiRestoreStandardFilterCriteria_(filterState);

    if (restored) {
      ocKakuteiThrowUserError_(
        '通常フィルタの絞り込み条件を解除できなかったため、' +
        '元の条件へ復元しました。フィルタ本体は削除していません。' +
        '手動非表示行だけは既に再表示されている可能性があります。' +
        '行グループの開閉状態は変更していません。' +
        '編集権限と保護設定を確認してください。',
      );
    }

    ocKakuteiThrowUserError_(
      '通常フィルタの絞り込み条件を解除できず、' +
      '一部の条件を元へ戻せない可能性があります。' +
      'フィルタ本体は削除していません。' +
      '行グループの開閉状態は変更していません。' +
      '対象シートのフィルタ条件と編集権限を確認してください。',
    );
  }
}

/**
 * 退避したフィルタ条件を全列へ再設定する。
 *
 * @return {boolean} 復元とflushに成功した場合true。
 */
function ocKakuteiRestoreStandardFilterCriteria_(filterState) {
  try {
    filterState.criteria.forEach(function (entry) {
      filterState.filter.setColumnFilterCriteria(
        entry.columnPosition,
        entry.criteria,
      );
    });
    SpreadsheetApp.flush();
    return true;
  } catch (restoreError) {
    return false;
  }
}

function ocKakuteiShowCopyDialog_(config, context, output) {
  var template = HtmlService.createTemplateFromFile(config.copyDialogFile);
  template.toolName = config.toolName;
  template.copyText = output.copyText;
  template.dateLabels = context.dateLabels;
  template.rowCount = output.rowCount;
  template.headerRow = context.headerRow;

  var html = template
    .evaluate()
    .setWidth(config.copyDialogWidth)
    .setHeight(config.copyDialogHeight);

  SpreadsheetApp.getUi().showModalDialog(
    html,
    config.toolName + ' - コピー確認',
  );
}

function ocKakuteiBuildInitialConfirmationMessage_(config, context) {
  return [
    '処理対象シートは「' + context.spreadsheetName + '：' +
      config.sourceSheetName + '」です。',
    context.headerRow + '行目をヘッダー行として検出し、' +
      context.dataStartRow + '行目以降を取得します。',
    '学籍番号・SA/TAは、前後の空白、全角文字、見えない文字を修正した値をコピーします。',
    '処理対象期間は「' + context.startDate.text + '～' +
      context.endDate.text + '」です。',
    '通常フィルタはフィルタ自体を残したまま各列の絞り込み条件だけを解除します。手動で非表示にされた行を再表示します。',
    '行グループは通常の非表示行とは別機能として扱い、開閉状態を変更しません。',
    'データ取得時はフリガナの昇順で取得されます。',
    '続行しますか。',
  ].join('\n\n');
}

function ocKakuteiValidateMaximumDateRange_(config, startDate, endDate) {
  var exclusiveLimit = Date.UTC(
    startDate.year + config.maxRangeYears,
    startDate.month - 1,
    startDate.day,
  );

  if (endDate.key >= exclusiveLimit) {
    ocKakuteiThrowUserError_(
      '指定可能な期間は最大' + config.maxRangeYears +
      '年間です。開始日と終了日を確認してください。',
    );
  }
}

/**
 * 必須識別子を検証し、コピーに使用する正規化済み値を返す。
 */
function ocKakuteiValidateRequiredAsciiAlphanumeric_(
  value,
  sheetRow,
  sourceColumnIndex,
  columnName
) {
  var normalized = ocKakuteiNormalizeIdentifier_(value);
  var cellA1 = ocKakuteiBuildCellA1_(sheetRow, sourceColumnIndex);

  if (normalized === '') {
    ocKakuteiThrowUserError_(
      'シート上の' + sheetRow + '行目（対象セル ' + cellA1 +
      '）の「' + columnName + '」が空欄です。検出値: ' +
      ocKakuteiDescribeValue_(value),
    );
  }

  ocKakuteiValidateNormalizedAsciiAlphanumeric_(
    normalized,
    value,
    sheetRow,
    sourceColumnIndex,
    columnName,
  );
  return normalized;
}

/**
 * 任意識別子を検証する。空欄は空文字として返す。
 */
function ocKakuteiValidateOptionalAsciiAlphanumeric_(
  value,
  sheetRow,
  sourceColumnIndex,
  columnName
) {
  var normalized = ocKakuteiNormalizeIdentifier_(value);
  if (normalized === '') {
    return '';
  }

  ocKakuteiValidateNormalizedAsciiAlphanumeric_(
    normalized,
    value,
    sheetRow,
    sourceColumnIndex,
    columnName,
  );
  return normalized;
}

function ocKakuteiValidateNormalizedAsciiAlphanumeric_(
  normalized,
  originalValue,
  sheetRow,
  sourceColumnIndex,
  columnName
) {
  if (!/^[A-Za-z0-9]+$/.test(normalized)) {
    var cellA1 = ocKakuteiBuildCellA1_(sheetRow, sourceColumnIndex);
    ocKakuteiThrowUserError_(
      'シート上の' + sheetRow + '行目（対象セル ' + cellA1 +
      '）の「' + columnName +
      '」は、空欄または半角英数字で入力してください。' +
      '検出値: ' + ocKakuteiDescribeValue_(originalValue) +
      ' / 正規化後: ' + ocKakuteiDescribeValue_(normalized),
    );
  }
}

/**
 * 識別子の前後空白、全角英数字、ゼロ幅文字を正規化する。
 */
function ocKakuteiNormalizeIdentifier_(value) {
  return String(value)
    .replace(/[\u200B-\u200D\u2060\uFEFF]/g, '')
    .normalize('NFKC')
    .trim();
}

/**
 * 日付状態値を正規化する。空文字または空白だけの値は空欄として扱う。
 */
function ocKakuteiNormalizeOptionalDateValue_(value) {
  var text = String(value);
  return ocKakuteiIsBlankDisplayValue_(text) ? '' : text;
}

function ocKakuteiIsBlankDisplayValue_(value) {
  return String(value)
    .replace(/[\u200B-\u200D\u2060\uFEFF]/g, '')
    .trim() === '';
}

/**
 * フリガナとして使用可能な文字か判定する。
 *
 * ASCII: 半角英数字、半角スペース、氏名で使用する半角記号
 *         - ' . / ( ) & _ ,
 * U+FF61～U+FF9F: 半角句読点、半角カタカナ、濁点・半濁点。
 */
function ocKakuteiIsAllowedFurigana_(value) {
  return /^[A-Za-z0-9 .,'()\/&_\-\uFF61-\uFF9F]+$/.test(String(value));
}

function ocKakuteiValidateFurigana_(value, sheetRow, sourceColumnIndex) {
  var cellA1 = ocKakuteiBuildCellA1_(sheetRow, sourceColumnIndex);
  if (value.trim() === '') {
    ocKakuteiThrowUserError_(
      'シート上の' + sheetRow + '行目（対象セル ' + cellA1 +
      '）の「フリガナ」が空欄です。',
    );
  }

  if (!ocKakuteiIsAllowedFurigana_(value)) {
    ocKakuteiThrowUserError_(
      'シート上の' + sheetRow + '行目（対象セル ' + cellA1 +
      '）の「フリガナ」に使用できない文字があります。' +
      '半角カタカナ、半角英数字、氏名用の半角記号' +
      '（-、\'、.、/、()、&、_、,）、半角スペースを使用してください。' +
      '検出値: ' + ocKakuteiDescribeValue_(value),
    );
  }
}

/**
 * 検査用にだけ正規化する。利用者の名前や元セルは書き換えない。
 */
function ocKakuteiIsFormulaLike_(value) {
  var inspected = String(value)
    .normalize('NFKC')
    .replace(/^[\s\u0000-\u001F\u007F\u200B-\u200D\u2060]+/, '');
  return /^[=+\-@]/.test(inspected);
}

function ocKakuteiValidateNoTsvControlCharacters_(
  config,
  outputValues,
  sheetRow,
  headerInfo,
  outputLabels
) {
  outputLabels = outputLabels || config.fixedHeaders.concat(
    headerInfo.targetDateColumns.map(function (column) {
      return column.confirmationLabel;
    }),
  );

  for (var index = 0; index < outputValues.length; index += 1) {
    if (/[\t\r\n]/.test(outputValues[index])) {
      var sourceColumnIndex = headerInfo.outputIndexes[index];
      ocKakuteiThrowUserError_(
        'シート上の' + sheetRow + '行目（対象セル ' +
        ocKakuteiBuildCellA1_(sheetRow, sourceColumnIndex) +
        '）の「' + outputLabels[index] +
        '」にタブまたは改行が含まれています。検出値: ' +
        ocKakuteiDescribeValue_(outputValues[index]),
      );
    }
    if (ocKakuteiIsFormulaLike_(outputValues[index])) {
      ocKakuteiThrowUserError_(
        'シート上の' + sheetRow + '行目（対象セル ' +
        ocKakuteiBuildCellA1_(sheetRow, headerInfo.outputIndexes[index]) +
        '）の「' + outputLabels[index] +
        '」は貼り付け先で数式になる可能性があります。' +
        '先頭の =、+、-、@ を確認してください。コピーは中止しました。',
      );
    }
  }
}

function ocKakuteiNormalizeFuriganaForSort_(value) {
  return String(value).trim().normalize('NFKC');
}

/**
 * 0始まりの列インデックスと1始まりの行番号からA1表記を作る。
 */
function ocKakuteiBuildCellA1_(sheetRow, sourceColumnIndex) {
  return ocKakuteiColumnNumberToLetters_(sourceColumnIndex + 1) + String(sheetRow);
}

function ocKakuteiColumnNumberToLetters_(columnNumber) {
  var number = columnNumber;
  var letters = '';

  while (number > 0) {
    var remainder = (number - 1) % 26;
    letters = String.fromCharCode(65 + remainder) + letters;
    number = Math.floor((number - 1) / 26);
  }

  return letters;
}

/**
 * 不可視文字を確認できるよう、値とUnicodeコードポイントを表示する。
 */
function ocKakuteiDescribeValue_(value) {
  var text = String(value);
  var characters = Array.from(text);
  var previewCharacters = characters.slice(0, 40);
  var preview = JSON.stringify(previewCharacters.join(''));
  if (characters.length > 40) {
    preview = preview.slice(0, -1) + '…"';
  }

  var codePoints = characters.slice(0, 20).map(function (character) {
    return 'U+' + character.codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
  });
  var codePointSuffix = characters.length > 20 ? ' ほか' : '';

  return preview + '（文字数 ' + characters.length +
    '、コードポイント ' +
    (codePoints.length > 0 ? codePoints.join(' ') : 'なし') +
    codePointSuffix + '）';
}

function ocKakuteiFormatRowNumberList_(rowNumbers) {
  var displayLimit = 20;
  var visibleRows = rowNumbers.slice(0, displayLimit);
  var suffix = rowNumbers.length > displayLimit
    ? 'ほか' + (rowNumbers.length - displayLimit) + '行'
    : '';
  return visibleRows.join('、') + (suffix ? '、' + suffix : '');
}

function ocKakuteiSha256Hex_(value) {
  var digest = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    value,
    Utilities.Charset.UTF_8,
  );

  return digest.map(function (byte) {
    var unsignedByte = byte < 0 ? byte + 256 : byte;
    return ('0' + unsignedByte.toString(16)).slice(-2);
  }).join('');
}

function ocKakuteiPrintableValue_(value) {
  if (value === '') {
    return '（空欄）';
  }

  var text = String(value);
  var maxLength = 80;
  return text.length > maxLength ? text.slice(0, maxLength) + '…' : text;
}

function ocKakuteiThrowUserError_(message) {
  var error = new Error(message);
  error.name = 'OC_KakuteiExtractorUserError';
  throw error;
}

function ocKakuteiToUserMessage_(error) {
  if (error && error.name === 'OC_KakuteiExtractorUserError') {
    return error.message;
  }
  return '処理中に予期しないエラーが発生しました。' +
    '再実行しても解消しない場合は管理者へ連絡してください。';
}

function ocKakuteiShowAlert_(config, ui, message) {
  ui.alert(config.toolName, message, ui.ButtonSet.OK);
}
