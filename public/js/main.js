const MAX_FILE_SIZE = 1048576
const timeout = 1500

// checkbox - on change
$('.custom-control-input').change(function() {
 // alert($(this).prop('checked'));
  // alert($(this).is('checked'));
  this.form.submit();
})

// check file sizes
$('#file_upload').change(function() {
  for (i=0; i<this.files.length; i++) {
    if(this.files[i].size > MAX_FILE_SIZE) {
      $('#file_upload').val('');
      alert(`One or more files exceeds max size limit of ${Math.round(MAX_FILE_SIZE/1000000)} MB.`);
      break;
    }
  }
});

$('#upload_form').submit(function(){
  if ( !$('#file_upload').val() ) {
    return false;
  }
});

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