if (! window._OQAjaxQueryLoaded)
(function(){
  window._OQAjaxQueryLoaded = true;
  var IS_IOS = /iPhone|iPod|iPad/.test(navigator.userAgent);

  window.OQnotify = function(thing) {
    var $oqmsg;
    if (thing.responseText) {
      $oqmsg = $("<div class=OQmsg />").html(thing.responseText)
      var $x = $oqmsg.find('.OQmsg');
      if ($x.length > 0) {
        $oqmsg = $x; 
      }
    }
    else {
      $oqmsg = $("<div class=OQmsg />").html(thing);
    }
    var $oqnotify = $("<div class=OQnotify><button type=button class=OQnotifyOkBut>close</button></div>");
    $oqnotify.prepend($oqmsg);
    $("div.OQnotify").remove();
    $oqnotify.appendTo('body').delay(6000).fadeOut(function(){ $(this).remove(); });
  };

  $(document).on('click',"a[href='#']", function(e){
    e.preventDefault();
    return true;
  });

  $(document).on('click',".OQnotifyOkBut", function(){
    $(this).closest('.OQnotify').remove();  
  });

  // show column panel when clicked
  $(document).on('click','table.OQdata thead td', function(e) {
    var $t = $(this);
    var $menu = $t.closest('form').find('.OQColumnCmdPanel');
    var $c = $menu.children().prop('disabled',false);
    var nosel=$t.is('[data-noselect]'),
        nofil=$t.is('[data-nofilter]'),
        canupdate=$t.is('[data-canupdate]'),
        nosort=$t.is('[data-nosort]');
    if (nosel && nofil && nosort) return true;
    if (nosel) $c.filter('.OQAddColumnsBut,.OQCloseBut').prop('disabled',true);
    if (nofil) $c.filter('.OQFilterBut').prop('disabled',true);
    if (nosort) $c.filter('.OQSortBut,.OQReverseSortBut').prop('disabled',true);
    if (canupdate) $c.filter('.OQUpdateDataToolBut').show(); 
    else $c.filter('.OQUpdateDataToolBut').hide();

    if ($t.is('.OQdataLHead[data-col]')) {
      $menu.data('OQdataFieldIdxCtx', undefined).data('OQdataCol', $t.attr('data-col'));
      $c.filter('.OQLeftBut,.OQRightBut,.OQCloseBut').prop('disabled',true);
    } else {
      var fieldIdx = $t.prevAll().length - 1; // don't count OQdataLCol,..
      var numFields = $t.parent().children().length - 2; // exclude OQdataLCol and OQdataRCol
      if (fieldIdx < 0 || fieldIdx >= numFields) return true;
      $menu.data('OQdataFieldIdxCtx', fieldIdx).data('OQdataCol', $t.attr('data-col'));
    }

    var left='unset', right='unset';
    if ($t[0].getBoundingClientRect().left + $menu.width() > $(window).width()) {
      right=0;
    }
    else {
      var clientX = (e.clientX > 0) ? e.clientX : $t.offset().left + ($t.width() / 2);
      left = clientX - $t.offset().left - ($menu.width() / 2);
      if (left < 0) left = 0;
    }
    $menu.appendTo($t).css('right', right).css('left', left).show();
    var hideMenu = function(){ $menu.hide(); $(document).off('.OQmenu'); };
    $(document).on('click.OQmenu', hideMenu).on('keydown.OQmenu', function(e){ if (e.which==27) { hideMenu(); e.preventDefault(); }});
    return true;
  });

  $(document).on('click','.OQRemoveSortBut', function(e) {
    e.preventDefault();
    var $t = $(this);
    var idx = $t.prevAll().length;
    var $form = $(this).closest('form');
    var $sort = $($form[0].sort);
    var sort = $sort.val().split(',');
    sort.splice(idx, 1);
    $sort.val(sort.join(','));
    var f = $form[0];
    $(f.page).val('1');
    if ($(f.rows_page).val()=='All') f.rows_page.selectedIndex=0;
    refreshDataGrid($form); 
    return true;
  });

  $(document).on('click','.OQCloseBut', function(e) {
    e.preventDefault();
    var $form = $(this).closest('form');
    var $menu = $form.find('.OQColumnCmdPanel');
    var fieldIdx = $menu.data('OQdataFieldIdxCtx');
    var $show = $($form[0].show);
    var show = $show.val().split(',');
    if (show.length > 1) {
      show.splice(fieldIdx, 1);
      $show.val(show.join(','));
      $menu.hide().appendTo($form); // ensure we do not delete menu
      $form.children('.OQdata').find('td:nth-child('+ (fieldIdx+2) +')').remove();
    }
    return true;
  });

  $(document).on('click','.OQLeftBut', function(e) {
    e.preventDefault();
    var $form = $(this).closest('form');
    var $menu = $form.find('.OQColumnCmdPanel');
    var fieldIdx = $menu.data('OQdataFieldIdxCtx');
    if (fieldIdx == 0) return true;
    var $show = $($form[0].show);
    var show = $show.val().split(',');
    var tmp = show[fieldIdx];
    show[fieldIdx] = show[fieldIdx - 1]
    show[fieldIdx - 1] = tmp;
    $show.val(show.join(','));
    $form.children('.OQdata').find('td:nth-child('+ (fieldIdx+2) +')')
      .each(function(){ $(this).insertBefore($(this).prev()); });
    $menu.data('OQdataFieldIdxCtx',fieldIdx - 1);
    return true;
  });

  $(document).on('click','.OQRightBut', function(e) {
    e.preventDefault();
    var $form = $(this).closest('form');
    var $menu = $form.find('.OQColumnCmdPanel');
    var fieldIdx = $menu.data('OQdataFieldIdxCtx');
    var $show = $($form[0].show);
    var show = $show.val().split(',');
    if (fieldIdx == (show.length - 1)) return true;
    var tmp = show[fieldIdx];
    show[fieldIdx] = show[fieldIdx + 1]
    show[fieldIdx + 1] = tmp;
    $show.val(show.join(','));
    $form.children('.OQdata').find('td:nth-child('+ (fieldIdx+2) +')')
      .each(function(){ $(this).insertAfter($(this).next()); });
    $menu.data('OQdataFieldIdxCtx',fieldIdx + 1);
    return true;
  });

  $(document).on('click','.OQSortBut,.OQReverseSortBut', function(e) {
    e.preventDefault();
    var $form = $(this).closest('form');
    var $menu = $form.find('.OQColumnCmdPanel');
    var colalias = $menu.data('OQdataCol');
    var re = new RegExp('\\b'+colalias+'\\b');
    var $sort = $($form[0].sort);
    var sort = ($sort.val()) ? $sort.val().split(',') : [];
    var newsort = [];
    for (var i=0,l=sort.length;i<l;++i) {
      if (! re.test(sort[i]))
        newsort.push(sort[i]);
    }
    newsort.push('['+colalias+']' + (/Reverse/.test(this.className)?' DESC':''));
    $sort.val(newsort.join(','));
    $($form[0].page).val('1');
    refreshDataGrid($form); 
  });

  var downloadCtr = 0;
  $(document).on('click','.OQDownloadCSV,.OQDownloadHTML,.OQDownloadXML,.OQDownloadJSON', function(){
    var target = 'download'+(downloadCtr++); 
    var $f = $('.OQform');
    var $panel = $(this).closest('.OQToolsPanel');
    var $newform = $('<form>').css('display','none').attr({
      action: $f.attr('action'), method: 'POST', target: target });
    var dat = buildParamMap($f);
    if (/CSV/.test(this.className)) dat.module = 'CSV';
    else if (/XML/.test(this.className)) dat.module = 'XML';
    else if (/JSON/.test(this.className)) dat.module = 'JSON';
    else dat.module = 'PrinterFriendly';
    if ($panel.find('.OQExportAllResultsInd:checked').length==1) {
      dat.rows_page = 'All';
      dat.page = 1;
    }
    for (var n in dat)
      $('<input>').attr({ name: n, value: dat[n] }).appendTo($newform);
    $('<iframe id='+target+' name='+target+' style="visibility: hidden; height: 1px;">').appendTo(document.body);
    $newform.appendTo(document.body);
    downloadCtr++;
    $newform.submit();
    $panel.find('.OQToolsCancelBut').click();
  });

  $(document).on('click','.OQToolsCancelBut', function(){
    $(".OQToolsPanel").hide();
  });

  $(document).on('click','.OQToolsBut', function(){
    var $p = $(".OQToolsPanel").toggle();
    $(".OQToolsPanel:visible .OQToolExpander > summary:first").focus().click();
  });

  $(document).on('click','.OQDeleteSavedSearchBut', function(){
    var $but = $(this);
    var $tr = $(this).closest('tr');
    var id = $tr.find('[data-id]').attr('data-id');
    var $f = $('.OQform');
    var dat = buildParamMap($f);
    dat.module = 'InteractiveQuery2Tools';
    dat.OQDeleteSavedSearch = id;
    $.ajax({ url: $f[0].action, type: 'POST', dataType: 'json',
      data: dat,
      complete: function(jqXHR) {
        if (/report\ deleted/.test(jqXHR.responseText)) {
          OQnotify("report deleted"); 
          $tr.remove();
        }
        else
          OQnotify('Could not delete report.' + jqXHR.responseText);
      }
    });
    return false;
  });

  var parseHour = function(h) {
    var rv = 0;
    if (/(\d+)/.test(h)) rv = parseInt(RegExp.$1,10);
    if (/AM/i.test(h) && rv == 12) rv = 0;
    else if (/PM/i.test(h) && rv < 12) rv+=12;
    if (rv >= 24) rv = 23;
    return rv;
  };

  $(document).on('click','.OQSaveNewReportBut,.OQSaveReportBut', function(e) {
    var $f = $('.OQform');
    var dat = buildParamMap($f);

    // if request to save new saved search
    if ($(this).hasClass('OQSaveNewReportBut')) dat.OQss='';

    dat.module = 'InteractiveQuery2Tools';
    dat.OQsaveSearchTitle = $("#OQsaveSearchTitle").val();
    if (! dat.OQsaveSearchTitle) {
      OQnotify('Enter a name.');
      return true;
    }
    dat.alert_mask = 0;
    if ($("#OQalertenabled").prop("checked")) {
      dat.alert_mask = 0; $("input[name=OQalert_mask]:checked").each(function(){ dat.alert_mask |= parseInt(this.value,10); });
      dat.alert_interval_min = parseInt($("#OQalert_interval_min").val(),10);

      if (dat.alert_mask==0) {
        OQnotify('Specify when to send the alert.');
        return true;
      }
      if (!(dat.alert_interval_min >= 30)) {
        OQnotify('Enter a "Check Every" minute hour value greater or equal to 30');
        return true;
      }

      dat.alert_dow = '';
      $(".OQalert_dow:checked").each(function(){ dat.alert_dow += this.value; });
      if (dat.alert_dow == '') {
        OQnotify('Select at least one "On Days".');
        return true;
      }

      dat.alert_start_hour = parseHour($("#OQalert_start_hour").val());
      if (! dat.alert_start_hour) {
        OQnotify('Enter a "From" hour between 0 and 23.');
        return true;
      }

      dat.alert_end_hour = parseHour($("#OQalert_end_hour").val());
      if (! dat.alert_end_hour) {
        OQnotify('Enter a "To" hour between 0 and 23.');
        return true;
      }

      if (dat.alert_start_hour > dat.alert_end_hour) {
        OQnotify('"From" hour must be less than "To" hour.');
        return true;
      }
    }
    
    // set this saved search as default
    if($('#OQsave_search_default').length > 0) {
      dat.save_search_default = $('#OQsave_search_default').prop('checked') ? 1 : 0;
    }
    
    $.ajax({ url: $f[0].action, type: 'POST', data: dat, dataType: 'json',
      error: function(){
        OQnotify("Could not save report.");
      },
      success: function(x) {
        if (x.id) {
          if (! $f[0].OQss) $("<input type=hidden name=OQss />").appendTo($f);
          $f[0].OQss.value=x.id;    
          $('.OQToolsCancelBut').click();
          OQnotify("report saved");
        }
        else {
          OQnotify("Could not save report. " + x.msg);
        }
      }
    });
    return true;
  });
  $(document).on('click', '#OQalertenabled', function(e) {
    if (this.checked) {
      $("#OQSaveReportEmailAlertOpts").addClass('opened');
      $("#OQsave_search_default").prop('checked',false);
    } else {
      $("#OQSaveReportEmailAlertOpts").removeClass('opened');
    }
  });

  $(document).on("click", "#OQsave_search_default", function(){
    if (this.checked) {
      $("#OQalertenabled").prop('checked',false);
    }
  });

  $(document).on('click','.OQAddColumnsBut', function(e) {
    e.preventDefault();
    var $f = $(this).closest('form');
    var dat = buildParamMap($f);
    dat.module = 'ShowColumns';
    $f.addClass('OQAddColumnsMode');
    $.ajax({ url: $f[0].action, type: 'POST', data: dat, dataType: 'html',
      complete: function(jqXHR) {
        try { 
          var $p = $('<div>').append(jqXHR.responseText).find('.OQAddColumnsPanel');
          if ($p.length!=1) throw(1);
          $f.append($p);
          $p[0].scrollIntoView(false);
        } catch(e) {
          OQnotify('Could not load add fields panel.');
          $f.removeClass('OQAddColumnsMode');
        }
      }
    });
    return true;
  });

  $(document).on('change','select.fieldToUpdate', function(e) {
    var $f = $(this).closest('form');
    var $panel = $(this).closest('.OQUpdateDataToolPanel');
    var dat = buildParamMap($f);
    dat.module = 'UpdateDataTool';
    dat = $.param(dat, true);
    dat += '&fields='+encodeURIComponent($(this).val());
    $.ajax({
      url: $f[0].action,
      type: 'POST',
      data: dat,
      dataType: 'html',
      complete: function(jqXHR) {
        try { 
          var $p = $('<div>').append(jqXHR.responseText).find('.OQUpdateDataToolPanel');
          if ($p.length!=1) throw(1);
          $panel.replaceWith($p);
          $p.find("input[name=values]:last").focus();
        } catch(e) {
          OQnotify('Could not update data panel.');
        }
      }
    });
  });
  
  $(document).on('click','.OQDelRow', function(e) {
    $(this).closest('tr').remove();
  });

  $(document).on('click','.OQUpdateDataToolBut', function(e) {
    e.preventDefault();
    var $f = $(this).closest('form');
    var $menu = $f.find('.OQColumnCmdPanel');
    var fieldIdx = $menu.data('OQdataFieldIdxCtx');
    var $show = $($f[0].show);
    var show = $show.val().split(',');
    var colalias = show[fieldIdx];
    var dat = buildParamMap($f);
    delete dat.show; delete dat.sort; delete dat.page; delete dat.rows_page;
    delete dat.on_select; delete dat.queryDescr;
    delete dat._oqcsrf;
    dat.fields = colalias;
    dat.module = 'UpdateDataTool';
    $f.addClass('OQUpdateDataToolMode');
    $.ajax({ url: $f[0].action, type: 'POST', data: dat, dataType: 'html',
      complete: function(jqXHR) {
        try { 
          var $p = $('<div>').append(jqXHR.responseText).find('.OQUpdateDataToolPanel');
          if ($p.length!=1) throw(1);
          $f.append($p);
          $p.find("input[name=values]:last").focus();
        } catch(e) {
          OQnotify('Could not load data panel.');
          $f.removeClass('OQUpdateDataToolMode');
        }
      }
    });
    return true;
  });
  $(document).on('click','.OQUpdateDataToolOKBut', function() {
    if (! window.confirm('Are you sure you want to update the field value of all records matching the filters of the report? Make sure you have reviewed all records in the report.')) return;
    var $but = $(this);
    $but.prop('disabled', true);

    var $f = $(this).closest('form');
    var $panel = $(this).closest('.OQUpdateDataToolPanel');
    var dat = buildParamMap($f);
    dat.module = 'UpdateDataTool';
    dat.act = 'save';
    delete dat.show; delete dat.sort; delete dat.page; delete dat.rows_page;
    delete dat.on_select; delete dat.queryDescr;
    dat = $.param(dat, true);

    $panel.find('.OQpanelMsg').empty().html("<center><b>Please wait ...<b></center>");

    var errorHandler = function(d) {
      $but.prop('disabled', false);
      var msg;
      if ('msg' in d) {
        msg = d.msg;
      } else if (d.responseText) {
        msg = $("<div />").html(d.responseText).text(); 
      }
      var $e = $("<div class=errmsg />").html('<strong>Error: </strong>');
      if (msg) {
        $e.append($('<pre />').text(msg));
      }
      $panel.find('.OQpanelMsg').empty().append($e);
    }
    $.ajax({
      url: $f[0].action,
      type: 'POST',
      data: dat,
      error: errorHandler,
      success: function(d) {
        if (d.status != 'ok') return errorHandler(d);
        $panel.find('.OQUpdateDataToolCancelBut').click();
        refreshDataGrid($f);
        OQnotify('data updated');
      }
    });
  });
  $(document).on('click','.OQUpdateDataToolCancelBut', function() {
    var $f = $(this).closest('form');
    $f.children('.OQUpdateDataToolPanel').remove();
    $f.removeClass('OQUpdateDataToolMode');
    return true;
  });

  $(document).on('click','.OQAddColumnsCancelBut', function() {
    var $f = $(this).closest('form');
    $f.children('.OQAddColumnsPanel').remove();
    $f.removeClass('OQAddColumnsMode');
    return true;
  });

  $(document).on('click','.OQAddColumnsOKBut', function() {
    var $panel = $(this).closest('.OQAddColumnsPanel');
    var $f = $panel.closest('form');
    var $menu = $f.find('.OQColumnCmdPanel');
    var fieldIdx = $menu.data('OQdataFieldIdxCtx');
    var $show = $($f[0].show);
    var show = $show.val().split(',');
    if (fieldIdx == '') fieldIdx = 0;
    var newshow = show.splice(0,fieldIdx + 1);
    $panel.find('input:checked').each(function(){ newshow.push(this.value); });
    $show.val(newshow.concat(show).join(','));
    $f.children('.OQAddColumnsPanel').remove();
    $f.removeClass('OQAddColumnsMode');
    refreshDataGrid($f);
    return true;
  });

  $(document).on('click','.OQToggleTableViewBut', function() {
    var $f = $(this).closest('form');
    $f[0].oqmode.value = ($f[0].oqmode.value=='recview') ? 'default' : 'recview';
    refreshDataGrid($f);
  });
  

  $(document).on('click','.OQToolExpander summary', function() {
    var $details = $(this).closest('details');

    // request to close
    if ($details.prop('open')) {
      $(this).nextAll().remove();
    }
    // request to open
    else {
      $details.parent().find('details[open] > summary').click(); // accordian behavior: close other opened sections
      var $newcontent = $("<div class=OQToolContent />");
      $details.append($newcontent);
      var $f = $('form.OQform');
      var dat = buildParamMap($f);
      dat.module = 'InteractiveQuery2Tools';
      dat.tool = $details.attr('data-toolkey');
      $newcontent.load($f[0].action, dat);
    }
  });

  $(document).on('click','.OQFilterDescr', function(e) {
    e.preventDefault();
    var $f = $(this).closest('form');
    var $menu = $f.find('.OQColumnCmdPanel');
    var fieldIdx = $menu.data('OQdataFieldIdxCtx');
    var $show = $($f[0].show);
    var show = $show.val().split(',');
    var colalias = show[fieldIdx];
    $f.nextAll('.OQFilterPanel').remove();
    var dat = buildParamMap($f);
    delete dat.show; delete dat.sort; delete dat.page; delete dat.rows_page;
    delete dat.on_select; delete dat.queryDescr;
    delete dat._oqcsrf;
    dat.module = 'InteractiveFilter2';
    $.ajax({ url: $f[0].action, type: 'POST', data: dat, dataType: 'html',
      complete: function(jqXHR) {
        if (jqXHR.status==0) return;
        var $p = $('<div>').append(jqXHR.responseText).find('.OQFilterPanel');
        if ($p.length==0) {
          OQnotify('Could not load add filter panel.');
          $f.removeClass('OQFilterMode');
        } else {
          $f.append($p);
          $p.find('.newfilter').focus();
          
        }
      }
    });
    $f.addClass('OQFilterMode');
    return true;
  });

  $(document).on('keydown','input.SaveReportNameInp', function(e){
    if (e.which==13)
      $(this).closest('fieldset').find('button').click();
    return true;
  });

  $(document).on('keydown','input.rexp', function(e){
    if (e.which==13)
      $(this).closest('.OQFilterPanel').find('button.OKFilterBut').click();
    return true;
  });

  $(document).on('click','.OQFilterBut', function(e) {
    e.preventDefault();
    var $f = $(this).closest('form');
    var $menu = $f.find('.OQColumnCmdPanel');
    var colalias = $menu.data('OQdataCol');
    $f.nextAll('.OQFilterPanel').remove();
    var dat = buildParamMap($f);
    delete dat.show; delete dat.sort; delete dat.page; delete dat.rows_page;
    delete dat.on_select; delete dat.queryDescr;
    delete dat._oqcsrf;
    dat.field = colalias;
    dat.module = 'InteractiveFilter2';
    $.ajax({ url: $f[0].action, type: 'POST', data: dat, dataType: 'html',
      context: $f,
      complete: function(jqXHR) {
        if (jqXHR.status==0) return;
        var $p = $('<div>').append(jqXHR.responseText).find('.OQFilterPanel');
        if ($p.length==0) {
          OQnotify('Could not load add filter panel.');
          $f.removeClass('OQFilterMode');
        } else {
          $f.append($p);
          $p[0].scrollIntoView(false);
          $p.find('input.rexp:last').focus().click();
        }
      }
    });
    $f.addClass('OQFilterMode');
    return true;
  });

  $(document.body).on('click','.OQeditBut,.OQnewBut', function(){
    var $t = $(this);
    var href = $t.attr('data-href') || $t.attr('href');
    var target = $t.attr('data-target') || $t.attr('target');
    if (target) OQopwin(href,target);
    else if (window.OQusePopups) OQopwin(href);
    else if ($t.is("button")) location = href;
    else return true;  // follow link as normal 
    return false;
  });

  $(document.body).on('click','.OQselectBut', function(){
    var f = this.form;
    var args = $(this).attr('data-rv');

    if (args=='') return true;
    var A = args.split('~~~');
    if (! f.on_select.value) {
      OQnotify('no on_select handler');
      return true;
    }
    var wo = window.opener2 || window.opener;

    var funcName = f.on_select.value.replace(/\,.*/,'');
    var funcRef = wo[funcName];
    if (! funcRef) {
      OQnotify('could not update parent form');
    } else {
      var opts = /(\~.*)/.test(f.on_select.value) ? RegExp.$1 : "";
      // Ahhh! can't use funcRef.apply with array args because
      // IE <= 7 can't pass Arrays created in one window to another
      funcRef(A[0],A[1],A[2],A[3],A[4],A[5],A[6],A[7],A[8],A[9]);
      if (/\bnoclose\b/.test(opts)) {
        $(this).fadeOut();
      } else {
        wo.focus();
        var wc = window.close2 || window.close;
        wc();
      }
    }
    return true;
  });

  $(document).on('click','.OQexportBut', function(e){
    e.preventDefault();
    var $f = $(this.form);
    var $dialog = $f.next().children('.OQExportDialog');
    $dialog.show();
  });
  

  $(document).on('click', '.OQrefreshBut', function(e) {
    e.preventDefault();
    refreshDataGrid($(this.form));
    return true;
  });

  $(document).on('change','.OQPager', function(e) {
    e.preventDefault();
    var $f = $(this).closest('form');
    refreshDataGrid($f);
    return true;
  });
  $(document).on('click','.OQNextBut', function(e) {
    e.preventDefault();
    var $f = $(this.form);
    var n = parseInt($f[0].page.value,10);
    $f[0].page.value = n + 1;
    refreshDataGrid($f);
    return true;
  });
  $(document).on('click','.OQPrevBut', function(e) {
    e.preventDefault();
    var $f = $(this.form);
    var n = parseInt($f[0].page.value,10);
    $f[0].page.value = n - 1;
    refreshDataGrid($f);
    return true;
  });

  $(document).on('submit','form.OQform', function(){
    return false;
  });

  $(document).on('change','select.rexp', function(){
    var $textbox = $(this).next();
    if (this.selectedIndex==0) {
      $textbox.show().focus();
    } else {
      $textbox.val('').hide();
    }
    return true;
  });

  $(document).on('click','button.DeleteFilterElemBut', function(){
    var $tr = $(this).closest('tr');
    if ($tr.next().length==1) $tr.next().remove();
    else if ($tr.prev().length==1) $tr.prev().remove();
    $tr.remove();
    return true;
  });

  $(document).on('click','button.CancelFilterBut', function(){
    $(this).closest('form').removeClass('OQFilterMode');
    $(this).closest('.OQFilterPanel').remove();
    return true;
  });

  $(document).on('click','tr.filterexp', function(){
    $("#filterinlinehelp").remove();
    var $tr = $(this);
    var type = $tr.find("select.lexp option[selected]").attr('data-type');
    var op = $tr.find("select.op").val();
    if (/date/.test(type) && /\=|\<|\>/.test(op)) {
      $tr.after("<tr id=filterinlinehelp><td colspan=6><small><strong>enter date in format:</strong> 2012-06-25, 2014-12-25 14:55, 2012-01-02 5:00PM<br><b>or calculation:</b> <em>today-60 days</em>, <em>today+1 month</em>, <em>today-5 years</em>, <em>today+ 200 minutes</em></small></td></tr>");
    }
  });

  $(document).on('click','button.OKFilterBut', function(){
    var $filterpanel = $(this).closest('.OQFilterPanel');
    var score = 0;
    var err;
    $filterpanel.find('select.lp,select.rp').each(function(){
      var x = this.selectedIndex;
      if (/^r/.test(this.className)) x*=-1;
      score += x;
      if (score < 0) err = "Extra ')' detected.";
    });
    if (score != 0) err = "Total '(' must equal total ')'.";
    if (err) OQnotify(err);
    else {
      var $f = $filterpanel.closest('form');
      var dat = buildParamMap($f);
      dat.filter = createFilterStr($filterpanel);
      delete dat.page; delete dat.rows_page;
      delete dat._oqcsrf;
      refreshDataGrid($f,dat);
    }
    return true;
  });

  $(document).on('click','button.lp', function(){
    $(this).replaceWith('<select class=lp><option></option><option selected>(<option>((<option>((</select>');
    return false;
  });
  $(document).on('change','select.lp', function(){
    if (this.selectedIndex==0) $(this).replaceWith('<button class=lp>(</button>');
    return true;
  });
  $(document).on('click','button.rp', function(){
    $(this).replaceWith('<select class=rp><option></option><option selected>)<option>))<option>))</select>');
    return false;
  });
  $(document).on('change','select.rp', function(){
    if (this.selectedIndex==0) $(this).replaceWith('<button class=rp>)</button>');
    return true;
  });

  // create a filter string from the widgets inside the filter panel
  var createFilterStr = function($filterpanel){
    var $elems = $filterpanel.find('input,select').filter(':enabled,:visible').not('select.newfilter');
    var newfilter='';

    for (var i=0, l=$elems.length; i<l; ++i) {
      var e=$elems[i], val=$.trim($(e).val());

      // if neccessary, quote rexp
      if ($(e).is('input.rexp') && (val=='' || /\W/.test(val))) {
        val='"'+val.replace(/\"/g,'')+'"'; // quote unless word
      }

      // if named filter, collect args
      else if ($(e).hasClass("nf_start")) {
        var args = [];
        while (++i < l) {
          e = $elems[i];
          if (/nf_end/.test(e.className)) break;
          if (e.disabled) continue;
          if ((e.type=='radio'||e.type=='checkbox') && !e.checked) continue;
          var arg_name=$.trim(e.name).replace(/^\_nfarg\d*/,'');
          if (arg_name!='') args.push(arg_name);
          var arg_val = $.trim($(e).val());
          if (arg_val=='' || /\W/.test(arg_val)) {
            args.push('"'+arg_val.replace(/\"/g,'')+'"');
          } else {
            args.push(arg_val);
          }
        }
        val += args.join(',') + ')';
      }

      if (/\w$/.test(newfilter) && /^\w/.test(val)) newfilter += ' '; // add space if neccessary
      newfilter += val;
    }
    return newfilter;
  };

  // when user select new filter element, add filter element to current fiter and
  // repaint filter panel
  $(document).on('change','select.newfilter', function(){
    var newexp = $(this).val();
    if (newexp=='') return true;
    this.selectedIndex = 0;
    if (! /\)$/.test(newexp)) newexp += '=""'; 
    var $filterpanel = $(this).closest('.OQFilterPanel');
    var newfilter = createFilterStr($filterpanel);
    if (newfilter != '') newfilter += ' AND ';
    newfilter += newexp;
    var $f = $(this).closest('form');
    var dat = buildParamMap($f);
    delete dat.show; delete dat.sort; delete dat.page; delete dat.rows_page;
    delete dat.on_select; delete dat.queryDescr;
    delete dat._oqcsrf;
    dat.module = 'InteractiveFilter2';
    dat.filter = newfilter;
    req = $.ajax({
      url: $f[0].action, type: 'POST', data: dat, dataType: 'html',
      complete: function(jqXHR) {
        try { 
          var $p = $('<div>').append(jqXHR.responseText).find('.OQFilterPanel');
          if ($p.length!=1) throw(1); 
          $f.children('.OQFilterPanel').replaceWith($p);
          $p.find('.rexp:last').focus();
        } catch(e) {
          OQnotify('Could not load data while processing new filter.');
        }
      }
    });
    return true;
  });
    
  $(document).keyup(function(evt) {
    var b;
    switch (evt.which) {
      case 37: b='.OQLeftBut'; break;
      case 39: b='.OQRightBut'; break;
      case 46: b='.OQCloseBut'; break;
    }
    if (b) {
      var $col = $(':hover[data-col]');
      if ($col.length != 1) return true;
      var idx = $col.prevAll().length - 1;
      var $form = $col.closest('form');
      var $menu = $form.find('.OQColumnCmdPanel');
      $menu.data('OQdataFieldIdxCtx', idx);
      $menu.children(b).click();
    }
    return true;
  });

  var buildParamMap = function($form) {
    var dat={};
    $('input,select',$form[0]).each(function(){
      // ignore named filter arguments
      if (this.name && ! /^\_nfarg\d+/.test(this.name)) {
        var n = this.name;
        var v = $.trim($(this).val());
        if (v=='' && !/^(show|filter|sort)$/.test(n)) {}
        else if (v=='1' && n=='page'){}
        else if (n=='oqmode' && v=='default'){}
        else if (n in dat) {
          if (! $.isArray(dat[n])) dat[n] = [dat[n]];
          dat[n].push(v);
        } else dat[n]=v;
      }
    });
    return dat;
  };

  window.OQgetShareURL = function($f, dat) {
    if (! $f) $f=$("form.OQform:first");
    if (! dat) dat = buildParamMap($f);
    delete dat.module;
    delete dat._oqcsrf;
    delete dat.OQss;
    delete dat.on_select;
    delete dat.page;
    delete dat.rows_page;
    if (dat.sort == '') delete dat.sort;
    var args = [];

    var datKeys = Object.keys(dat).sort();
    for (var i=0,l=datKeys.length;i<l;++i) {
      var name=datKeys[i];
      args.push(name+'='+encodeURIComponent(dat[name]));
    }
    args = args.join('&').replace(/\%20/g,'+').replace(/\%2C/g,',');
    var url = $f[0].action.replace(/\?.*/,'') + '?' + args;
    return url;
  };

  window.OQgetURL = function($f,dat) {
    if (! $f) $f=$("form.OQform:first");
    if (! dat) dat = buildParamMap($f);
    delete dat.module;
    delete dat._oqcsrf;
    var args = [];

    var datKeys = Object.keys(dat).sort();
    for (var i=0,l=datKeys.length;i<l;++i) {
      var name=datKeys[i];
      args.push(name+'='+encodeURIComponent(dat[name]));
    }
    args = args.join('&').replace(/\%20/g,'+').replace(/\%2C/g,',');
    var url = $f[0].action.replace(/\?.*/,'') + '?' + args;
    return url;
  };

  var refreshDataGrid = function($f,dat,retainScroll) {
    $f.addClass('LoadingData');

    if (! dat) dat = buildParamMap($f);
    delete dat.module;
    delete dat._oqcsrf;

    history.replaceState(null, null, OQgetURL($f, dat));
    parent.history.replaceState(null, null, OQgetURL($f, dat));
    return $.ajax({
      url: $f[0].action.replace(/\?.*/,''),
      type: 'post',
      data: dat,
      error: function() {
        OQnotify('Could not load data for data grid after error.');
        $f.removeClass('LoadingData');
      },
      success: function(d) {
        var $OQdoc = $("<div />").append(d).find(".OQdoc");
        if ($OQdoc.length != 1) {
          OQnotify('Could not load data for data grid after error.');
          $f.removeClass('LoadingData');
        } else {
          $(".OQdoc").replaceWith($OQdoc);
          if (! retainScroll) {
            $(window).scrollTop($f.scrollTop());
            if (IS_IOS) {
              $(parent).scrollTop($f.scrollTop());
            }
          }
          $(window).trigger('OQrefreshDataGridComplete');
        }
      }
    });
  };

  window.OQrefresh = function(updated_uid,p1,p2,p3,p4,p5,p6,p7,p8) {
    var $f = $('form.OQform').eq(0);
    var isClosed = false;

    // get parent function to call if one exists
    // strip away optional arguments and non word chars
    var func = $.trim($($f[0].on_select||$f[0].on_update).val()).replace(/\,.*/,'').replace(/\W/g,'');
    var is_on_select = /\w/.test($.trim($($f[0].on_select).val()));

    if (updated_uid && func) {
      try {
        var wo = window.opener2 || window.opener;
        wo[func](updated_uid,p1,p2,p3,p4,p5,p6,p7,p8);
        if (is_on_select) {
          var wc = window.close2 || window.close;
          wc();
          isClosed = true;
        }
      } catch(e) {}
    }
    if (! isClosed) {
      var dat = buildParamMap($f);
      if (updated_uid) dat.updated_uid = updated_uid;
      var $ajax = refreshDataGrid($f,dat,true);
    }
  };

  

  if (window.opwin) window.OQopwin=window.opwin;
  else window.OQopwin = function(lnk,target,opts,w,h) {
    if (! target) target = '_blank';
    if (! opts) opts = 'resizable,scrollbars';
    if (! w && window.OQWindowWidth) w = window.OQWindowWidth;
    if (! w) w = 800;
    if (! h && window.OQWindowHeight) h = window.OQWindowHeight;
    if (! h) h = 600;
    if (window.screen) {
      var s = window.screen;
      var max_width = s.availWidth - 10;
      var max_height = s.availHeight - 30;
      if (opts.indexOf('toolbar',0) != -1) max_height -= 40;
      if (opts.indexOf('menubar',0) != -1) max_height -= 35;
      if (opts.indexOf('location',0) != -1)max_height -= 35;
      var width  = (w > max_width)?max_width:w;
      var height = (h > max_height)?max_height:h;
      var par_left_offset = (window.screenX == null)?0:window.screenX;
      var par_top_offset  = (window.screenY == null)?0:window.screenY;
      var par_width;
      if (window.outerWidth != null) {
        par_width = window.outerWidth;
        if (par_width < width)
          par_left_offset -= parseInt((width - par_width)/2);
      } else
        par_width = max_width;

      var par_height;
      if (window.outerHeight != null) {
        par_height = window.outerHeight;
        if (par_height < height) {
          par_top_offset -= parseInt((height - par_height)/2);
        }
      } else
        par_height = max_height;

      var left = parseInt(par_width /2 - width /2) + par_left_offset;
      var top  = parseInt(par_height/2 - height/2) + par_top_offset;

      var newopts = 'width='+width+',height='+height+',left='+left+',top='+top;
      opts = (opts && opts != '')?newopts+','+opts:newopts;
    }
    var wndw = window.open(lnk,target,opts);
    if (wndw.focus) wndw.focus();
    return wndw;
  };

  // if on_select button exists, make sure it is always visisble on screen even if there is a horizontal scrollbar
  $(function(){
    if ($('input[name=on_select]').length > 0) {
      // find css rule that impacts the OQdataRCol position
      var cssRule;
      for (var r of $("#OQIQ2CSS").prop('sheet').cssRules) {
        if (r instanceof CSSStyleRule && r.selectorText=='td.OQdataRCol, td.OQdataRHead') {
          cssRule = r;
          break;
        }
      }
      if (! cssRule) throw('could not find td.OQdataRCol, td.OQdataRHead rule in sheet #OQIQ2CSS');
      var resizeTimer;
      var resizeHandler = function() {
        var $rcol = $(".OQdataRCol:first");
        if ($rcol.children().length > 0) {
          var rcolOffsetLeft = $(".OQdataRHead").prev().offset().left + $(".OQdataRHead").prev().width();
          var leftDelta = 0;
          if ((rcolOffsetLeft + $rcol.width()) > $(window).width()) {
            leftDelta = (rcolOffsetLeft - $('.OQform').width() + $rcol.width() + 10 - $(window).scrollLeft()) * -1;
            if (leftDelta > -1) leftDelta = 0;
          }
          if (cssRule.style.left != leftDelta) {
            cssRule.style.left = leftDelta + 'px';
          }
          cssRule.style.visibility = 'visible';
        }
      };
      var scheduleResizeHandlerCall = function() {
        if (cssRule.style.left != '0px') cssRule.style.visibility = 'hidden';
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(resizeHandler, 500);
      };
      $(window).resize(scheduleResizeHandlerCall).scroll(scheduleResizeHandlerCall);
      $(window).on('OQrefreshDataGridComplete', resizeHandler);
      resizeHandler();
    }
  });
})();
