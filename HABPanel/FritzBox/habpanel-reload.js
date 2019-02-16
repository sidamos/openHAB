angular
 .module('app.widgets')
 .controller('MyWidgetCtrl', testCtrl);

testCtrl.$inject = ['$scope', 'OHService'];
function testCtrl($scope, OHService) {
  var vm = this;
  vm.listDate = "123";

  OHService.onUpdate($scope, 'ListDate', function () {
    var item = OHService.getItem('ListDate');
    if (item && item.state != vm.listDate) {
      console.log("ListDate updated: " + item.state);
      vm.listDate = item.state;
    }
  });
}

