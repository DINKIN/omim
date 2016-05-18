#include "testing/testing.hpp"

#include "routing/routing_integration_tests/routing_test_tools.hpp"

#include "routing/route.hpp"

using namespace routing;
using namespace routing::turns;

UNIT_TEST(RussiaMoscowSevTushinoParkBicycleWayTurnTest)
{
  TRouteResult const routeResult = integration::CalculateRoute(
      integration::GetBicycleComponents(), MercatorBounds::FromLatLon(55.87467, 37.43658),
      {0.0, 0.0}, MercatorBounds::FromLatLon(55.8719, 37.4464));

  Route const & route = *routeResult.first;
  IRouter::ResultCode const result = routeResult.second;
  TEST_EQUAL(result, IRouter::NoError, ());

  integration::TestTurnCount(route, 1);

  integration::GetNthTurn(route, 0).TestValid().TestDirection(TurnDirection::TurnLeft);

  integration::TestRouteLength(route, 752.);
}

UNIT_TEST(RussiaMoscowGerPanfilovtsev22BicycleWayTurnTest)
{
  TRouteResult const routeResult = integration::CalculateRoute(
      integration::GetBicycleComponents(), MercatorBounds::FromLatLon(55.85630, 37.41004),
      {0.0, 0.0}, MercatorBounds::FromLatLon(55.85717, 37.41052));

  Route const & route = *routeResult.first;
  IRouter::ResultCode const result = routeResult.second;
  TEST_EQUAL(result, IRouter::NoError, ());

  integration::TestTurnCount(route, 2);

  integration::GetNthTurn(route, 0).TestValid().TestDirection(TurnDirection::TurnLeft);
  integration::GetNthTurn(route, 1).TestValid().TestDirection(TurnDirection::TurnLeft);
}

UNIT_TEST(RussiaMoscowSalameiNerisPossibleTurnCorrectionBicycleWayTurnTest)
{
  TRouteResult const routeResult = integration::CalculateRoute(
      integration::GetBicycleComponents(), MercatorBounds::FromLatLon(55.85159, 37.38903),
      {0.0, 0.0}, MercatorBounds::FromLatLon(55.85157, 37.38813));

  Route const & route = *routeResult.first;
  IRouter::ResultCode const result = routeResult.second;
  TEST_EQUAL(result, IRouter::NoError, ());

  integration::TestTurnCount(route, 1);

  integration::GetNthTurn(route, 0).TestValid().TestDirection(TurnDirection::TurnSlightRight);
}

UNIT_TEST(RussiaMoscowSevTushinoParkBicycleOnePointTurnTest)
{
  m2::PointD const point = MercatorBounds::FromLatLon(55.8719, 37.4464);
  TRouteResult const routeResult = integration::CalculateRoute(
      integration::GetBicycleComponents(), point, {0.0, 0.0}, point);

  Route const & route = *routeResult.first;
  IRouter::ResultCode const result = routeResult.second;
  TEST_EQUAL(result, IRouter::NoError, ());
  TEST_EQUAL(route.GetTurns().size(), 0, ());
  integration::TestRouteLength(route, 0.0);
}
