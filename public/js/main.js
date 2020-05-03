const MAX_FILE_SIZE = 1048576
const timeout = 1500

var weatherPopoverVisible = false;

// checkbox - on change
$('.custom-control-input').change(function() {
 // alert($(this).prop('checked'));
  // alert($(this).is('checked'));

  document.getElementById("save-change-spinner").style.display = "block";
  document.getElementById("save-change-spinner-label").style.display = "block";

  this.form.submit();
})

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

  document.getElementById("save-change-spinner").style.display = "none";
  document.getElementById("save-change-spinner-label").style.display = "none";

});

$(function () {
  $('[data-toggle="popover"]').popover({html:true});
})

