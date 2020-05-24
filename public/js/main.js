const MAX_FILE_SIZE = 1048576
const timeout = 1500

var weatherPopoverVisible = false;




// checkbox - on change
// $('.custom-control-input').change(function() {
//  // alert($(this).prop('checked'));
//   // alert($(this).is('checked'));

//   $("#save-change-spinner").show();
//   $("#save-change-spinner-label").show();


//   this.form.submit();
// })

// check file sizes
$('#chosen_file').change(function() {
  for (i=0; i<this.files.length; i++) {
    if(this.files[i].size > MAX_FILE_SIZE) {
      $('#file_upload').val('');
      alert(`One or more files exceeds max size limit of ${Math.round(MAX_FILE_SIZE/1000000)} MB.`);
      break;
    }
  }
});

$('#upload_form').submit(function(){
  if ( !$('#chosen_file').val() ) {
    return false;
  }
});

function logOut() {
  $.ajax({
    type: "POST",
    url: "/user/logout",
    data: {},
    success: function(data){
      window.location.href = data;
    }
  });
}

function getWeather() {
  $.ajax({
    type: "get",
    url: "/weather",
    data: {},
    success: function(data){
      document.getElementById("weather_btn").setAttribute("data-content", data);

      if (weatherPopoverVisible == true) {
        $('#weather_btn').popover('show');
      }
    }
  });
}

$('#weather_btn').on('hidden.bs.popover', function () {
  weatherPopoverVisible = false;
})

$('#weather_btn').on('shown.bs.popover ', function () {
  weatherPopoverVisible = true;
})



function loadDoc() {
  var xhttp = new XMLHttpRequest();

  setTimeout(function() {
    $('.alert').alert('close');

  }, timeout);

  xhttp.onreadystatechange = function() {
    if (this.readyState == 4 && this.status == 200) {
     document.getElementById("demo").innerHTML = this.responseText;
   }
 };

 xhttp.open("post", "/save_changes_tracker", true);
 xhttp.send();
}

// function reloadDates(endDate_str) {

//   var xhttp = new XMLHttpRequest();


// }




$(document).ready(function(){

  // for tracker page
  $(".custom-control-input").change(function(e) {

     var form = $(this.form);
     var url = form.attr('action');

     $.ajax({
       type: "POST",
       url: url,
           data: form.serialize(), // serializes the form's elements.
           success: function(data)
           {
              $('#save-changes').show();
              // $('.debug').html(data);
              // var json = JSON.parse(data);
              // $('.toast-header-text').html(json.toast_title);
              // $('.toast-body').html(json.toast_msg);
              //  $('.toast').toast('show');

              // if (json.type == 'success') {
              //   $('#toast-header-text').addClass('text-success');
              //   $('#toast-header-text').removeClass('text-danger');
              // } else {
              //   $('#toast-header-text').removeClass('text-success');
              //   $('#toast-header-text').addClass('text-danger');
              // }

            }
           });

  });


  $("#form-save-tracker-changes").on('submit', function(e) {
    // $("#save-change-spinner").show();
    // $("#save-change-spinner-label").show();
    $('#modal-saving-changes').modal('show');
  });

  // for exercise library page
  $(".template-form").on('submit', function(e) {
     e.preventDefault(); // avoid to execute the actual submit of the form.

     var form = $(this);
     var url = form.attr('action');

     $.ajax({
       type: "POST",
       url: url,
           data: form.serialize(), // serializes the form's elements.
           success: function(data)
           {
              var json = JSON.parse(data);
              $('.toast-header-text').html(json.toast_title);
              $('.toast-body').html(json.toast_msg);
               $('.toast').toast('show');

              if (json.type == 'success') {
                $('#toast-header-text').addClass('text-success');
                $('#toast-header-text').removeClass('text-danger');
              } else {
                $('#toast-header-text').removeClass('text-success');
                $('#toast-header-text').addClass('text-danger');
              }

            }
           });

   });

  // enable bootstrap tooltip
  $('[data-toggle="tooltip"]').tooltip();



  // highlight active link in nav bar
  // $( ".nav-item" ).bind( "click", function(event) {

  //       var clickedItem = $( this );
  //       $( ".nav-item" ).each( function() {
  //           $( this ).removeClass( "active" );
  //       });
  //       clickedItem.addClass( "active" );
  //   });

  $("#save-change-spinner").hide();
  $("#save-change-spinner-label").hide();
  $('#modal-saving-changes').modal('hide');

  // hide save changes button
  $('#save-changes').hide();

  // document.getElementById("save-change-spinner").style.display = "none";
  // document.getElementById("save-change-spinner-label").style.display = "none";

  if ($('#toast-content').text().trim() !== '') {
    $('.toast').toast('show');
  }

  // $("#toast-btn").click(function(){
  //   $('.deactivate-user-success').toast('show');
  // });






});

$(function () {
  $('[data-toggle="popover"]').popover({html:true});
})

// When adding new exercise template, show current subgroups based on selected level 1 group
$(function(){
    $('#group_lvl_1').on('change', function(){
        var val = $(this).val();
        var sub = $('#grouplist_lvl_2');
        $('option', sub).filter(function(){
            if (
                 $(this).attr('data-group') === val
              || $(this).attr('data-group') === 'SHOW'
            ) {
                $(this).attr('value', $(this).attr('hidden-value'));
            } else {
                $(this).attr('value', '');
            }
        });
    });
    $('#group_lvl_1').trigger('change');
});


function goBack() {
  window.history.back();
}